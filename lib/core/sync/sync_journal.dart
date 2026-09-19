import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../shared/database/app_database.dart';
import 'sync_row_codec.dart';

/// How long a deleted row stays recoverable.
///
/// Automatic sync carries a mistaken delete to every other device within
/// seconds, which closes the window in which the user could say "wait, that
/// was wrong". The trash reopens it.
const Duration kSyncTrashRetention = Duration(days: 30);

/// The local outbox for automatic sync.
///
/// Every method here is meant to be called **inside the transaction that made
/// the change**. Recording the operation separately would let a crash land the
/// write and lose the operation, and an operation that never existed is a
/// change that silently never syncs.
final class SyncJournal {
  final AppDatabase db;
  final String Function() _newId;

  SyncJournal({required this.db, String Function()? newId})
    : _newId = newId ?? const Uuid().v4;

  /// Runs [write] and records an `upsert` for the row it touched.
  ///
  /// The write is wrapped rather than followed, for two reasons. The row as it
  /// was before the change can only be read before the write happens, and
  /// nothing outside this method needs to remember to record afterwards -- a
  /// write that forgets is a change that silently never syncs.
  ///
  /// The operation carries the whole row, not a field diff: conflicts are
  /// resolved at entity level, so the winning operation has to reconstruct the
  /// row on its own. A diff would leave the losing side's untouched fields
  /// wiped rather than merged.
  Future<T> upsert<T>({
    required String entityType,
    required String entityId,
    required Future<T> Function() write,
  }) => db.transaction(() async {
    final before = await SyncRowCodec.read(db, entityType, entityId);

    final result = await write();

    final payload = await SyncRowCodec.read(db, entityType, entityId);
    // The write left no row: there is nothing to tell anyone about, and
    // inventing an operation for it would send a payload that does not exist.
    if (payload == null) return result;

    await _write(
      entityType: entityType,
      entityId: entityId,
      operation: 'upsert',
      payload: jsonEncode(payload),
      before: before == null ? null : jsonEncode(before),
    );

    // An id that is written again is no longer deleted. Leaving the tombstone
    // would make this device drop its own row the next time it reconciled.
    await (db.delete(db.syncTombstones)..where(
          (t) => t.entityType.equals(entityType) & t.entityId.equals(entityId),
        ))
        .go();

    return result;
  });

  /// Runs [write], which deletes the row, and records the delete -- along with
  /// everything the database deletes or rewrites on its way out.
  ///
  /// The body is read before [write] runs: after the delete there is nothing
  /// left to keep, and the body is what makes the delete undoable.
  ///
  /// The cascade matters as much as the row itself. Deleting a host takes its
  /// port forwards and bookmarks with it, and deleting an identity leaves
  /// every host that used it with a null. A device that is only told about the
  /// host keeps the orphans forever, and nothing about that looks like a bug
  /// until someone opens the tunnel list on the other device.
  Future<T> delete<T>({
    required String entityType,
    required String entityId,
    required Future<T> Function() write,
  }) => db.transaction(() async {
    final body = await SyncRowCodec.read(db, entityType, entityId);

    // Read both sets of consequences while the rows are still there.
    final cascaded = body == null
        ? const <({String type, String id})>[]
        : await _cascadeTargets(entityType, entityId);
    final rewritten = body == null
        ? const <({String type, String id})>[]
        : await _setNullTargets(entityType, entityId);

    final bodies = <({String type, String id}), String>{
      for (final target in cascaded)
        if (await SyncRowCodec.read(db, target.type, target.id) case final row?)
          target: jsonEncode(row),
    };

    final result = await write();

    // The row was not there to begin with. Recording a delete for it would
    // put a tombstone in the way of an `upsert` that may still be in flight
    // from another device.
    if (body == null) return result;

    await _recordDelete(entityType, entityId, jsonEncode(body));

    for (final entry in bodies.entries) {
      await _recordDelete(entry.key.type, entry.key.id, entry.value);
    }

    // These rows still exist; the database only nulled a column. They are
    // changes like any other, so they go out as upserts.
    for (final target in rewritten) {
      final payload = await SyncRowCodec.read(db, target.type, target.id);
      if (payload == null) continue;

      await _write(
        entityType: target.type,
        entityId: target.id,
        operation: 'upsert',
        payload: jsonEncode(payload),
        before: null,
      );
    }

    return result;
  });

  Future<void> _recordDelete(
    String entityType,
    String entityId,
    String body,
  ) async {
    final clock = await _nextClock();

    await _write(
      entityType: entityType,
      entityId: entityId,
      operation: 'delete',
      payload: null,
      before: body,
      clock: clock,
    );

    await db
        .into(db.syncTombstones)
        .insertOnConflictUpdate(
          SyncTombstonesCompanion.insert(
            entityType: entityType,
            entityId: entityId,
            body: Value(body),
            logicalClock: clock,
            deletedAt: DateTime.now(),
          ),
        );
  }

  /// Operations waiting to be sent, oldest first.
  Future<List<PendingOperation>> pending() => (db.select(
    db.pendingOperations,
  )..orderBy([(t) => OrderingTerm.asc(t.logicalClock)])).get();

  /// Drops the operations that were accepted by the server.
  ///
  /// Only the rows still holding the clock they were sent with: a row that
  /// changed again while the request was in flight is a newer operation that
  /// has not been sent, and dropping it would lose that change.
  Future<void> clearSent(Iterable<PendingOperation> sent) async {
    for (final operation in sent) {
      await (db.delete(db.pendingOperations)..where(
            (t) =>
                t.id.equals(operation.id) &
                t.logicalClock.equals(operation.logicalClock),
          ))
          .go();
    }
  }

  /// Rows this device deleted that can still be brought back.
  Future<List<SyncTombstone>> trash() =>
      (db.select(db.syncTombstones)
            ..where((t) => t.body.isNotNull())
            ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]))
          .get();

  /// True when this device deleted [entityId] and has not written it since.
  ///
  /// A pull consults this before applying an `upsert`: delete and rewrite
  /// arriving out of order is the most commonly reported way a home-grown sync
  /// resurrects a row the user deleted.
  Future<bool> isDeleted({
    required String entityType,
    required String entityId,
  }) async {
    final row =
        await (db.select(db.syncTombstones)..where(
              (t) =>
                  t.entityType.equals(entityType) & t.entityId.equals(entityId),
            ))
            .getSingleOrNull();

    return row != null;
  }

  /// Empties the body of every tombstone past [retention], keeping the id.
  ///
  /// The id has to outlive the body: without it a late `upsert` would bring
  /// the row back.
  Future<int> purgeTrash({Duration retention = kSyncTrashRetention}) async {
    final cutoff = DateTime.now().subtract(retention);

    // `<=`, not `<`: timestamps are stored to the second, so a row deleted in
    // the same second as the cutoff would otherwise never expire under a zero
    // retention. At the end of its window is expired.
    return (db.update(db.syncTombstones)..where(
          (t) => t.body.isNotNull() & t.deletedAt.isSmallerOrEqualValue(cutoff),
        ))
        .write(const SyncTombstonesCompanion(body: Value(null)));
  }

  /// Empties the trash now, at the user's request.
  Future<int> emptyTrash() =>
      (db.update(db.syncTombstones)..where((t) => t.body.isNotNull())).write(
        const SyncTombstonesCompanion(body: Value(null)),
      );

  /// The clocks this device is working from, creating the row on first use.
  Future<SyncStateData> readState() async {
    final existing = await (db.select(
      db.syncState,
    )..where((t) => t.id.equals(1))).getSingleOrNull();

    if (existing != null) return existing;

    await db
        .into(db.syncState)
        .insert(
          const SyncStateCompanion(id: Value(1)),
          mode: InsertMode.insertOrIgnore,
        );

    return (db.select(db.syncState)..where((t) => t.id.equals(1))).getSingle();
  }

  /// Adopts a clock seen from elsewhere.
  ///
  /// Lamport: this device's clock never goes backwards, and the next change it
  /// makes is ordered after everything it has seen.
  Future<void> observeClock(int clock) async {
    final state = await readState();
    if (clock <= state.lastSeenClock) return;

    await (db.update(db.syncState)..where((t) => t.id.equals(1))).write(
      SyncStateCompanion(lastSeenClock: Value(clock)),
    );
  }

  /// Marks the log as pulled through [clock].
  ///
  /// Only ever called after the operations it covers are durably written. A
  /// cursor advanced first turns an interrupted sync into permanent data loss:
  /// the skipped operations are never offered again.
  Future<void> acknowledgePull(int clock) async {
    await observeClock(clock);

    await (db.update(db.syncState)..where((t) => t.id.equals(1))).write(
      SyncStateCompanion(pulledThroughClock: Value(clock)),
    );
  }

  Future<int> _nextClock() async {
    final state = await readState();
    final next = state.lastSeenClock + 1;

    await (db.update(db.syncState)..where((t) => t.id.equals(1))).write(
      SyncStateCompanion(lastSeenClock: Value(next)),
    );

    return next;
  }

  /// Writes one operation, replacing any pending operation for the same row.
  ///
  /// Replacing rather than appending is the coalescing rule: with entity level
  /// last-writer-wins the intermediate states mean nothing to any receiver, so
  /// sending them would spend a 30-per-minute write budget on states nobody
  /// applies. The `before_image` of the first operation is carried forward --
  /// it is the common ancestor, and the second change is not.
  Future<void> _write({
    required String entityType,
    required String entityId,
    required String operation,
    required String? payload,
    required String? before,
    int? clock,
  }) async {
    final existing =
        await (db.select(db.pendingOperations)..where(
              (t) =>
                  t.entityType.equals(entityType) & t.entityId.equals(entityId),
            ))
            .getSingleOrNull();

    // The ancestor of a coalesced operation is the state before the *first*
    // change, not before the last one. The second change's "before" is a state
    // no other device ever saw.
    final beforeImage = existing?.beforeImage ?? before;

    if (existing != null) {
      await (db.delete(
        db.pendingOperations,
      )..where((t) => t.id.equals(existing.id))).go();
    }

    await db
        .into(db.pendingOperations)
        .insert(
          PendingOperationsCompanion.insert(
            id: _newId(),
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            payload: Value(payload),
            beforeImage: Value(beforeImage),
            logicalClock: clock ?? await _nextClock(),
            createdAt: DateTime.now(),
          ),
        );
  }

  /// Rows the database deletes when their parent goes, by foreign key.
  ///
  /// Mirrors `ON DELETE CASCADE` in the schema. Kept as data rather than
  /// discovered at run time: SQLite does not report what a cascade removed, so
  /// the only way to record those deletes is to know what they will be.
  static const Map<String, List<(String, String)>> cascades = {
    'workspaces': [
      ('identities', 'workspace_id'),
      ('host_groups', 'workspace_id'),
      ('hosts', 'workspace_id'),
      ('snippets', 'workspace_id'),
      ('runbooks', 'workspace_id'),
      ('templates', 'workspace_id'),
      ('bookmarks', 'workspace_id'),
    ],
    'hosts': [('port_forward_rules', 'host_id'), ('bookmarks', 'host_id')],
    'runbooks': [('runbook_steps', 'runbook_id')],
    'templates': [
      ('template_panes', 'template_id'),
      ('bookmarks', 'template_id'),
    ],
  };

  /// Rows the database rewrites when their parent goes, by foreign key.
  ///
  /// Mirrors `ON DELETE SET NULL`. These rows survive with a column cleared,
  /// so they are ordinary changes and go out as upserts.
  static const Map<String, List<(String, String)>> setNulls = {
    'host_groups': [('host_groups', 'parent_id'), ('hosts', 'group_id')],
    'identities': [('hosts', 'identity_id')],
    'hosts': [('hosts', 'jump_host_id')],
  };

  /// Everything a delete of [entityType]/[entityId] takes with it, including
  /// what those rows take with them in turn.
  Future<List<({String type, String id})>> _cascadeTargets(
    String entityType,
    String entityId,
  ) async {
    final found = <({String type, String id})>[];
    final seen = <String>{'$entityType/$entityId'};
    var frontier = [(type: entityType, id: entityId)];

    while (frontier.isNotEmpty) {
      final next = <({String type, String id})>[];

      for (final parent in frontier) {
        for (final (childTable, column)
            in cascades[parent.type] ?? const <(String, String)>[]) {
          for (final id in await _idsWhere(childTable, column, parent.id)) {
            if (!seen.add('$childTable/$id')) continue;

            final child = (type: childTable, id: id);
            found.add(child);
            next.add(child);
          }
        }
      }

      frontier = next;
    }

    return found;
  }

  Future<List<({String type, String id})>> _setNullTargets(
    String entityType,
    String entityId,
  ) async {
    final targets = <({String type, String id})>[];

    for (final (table, column)
        in setNulls[entityType] ?? const <(String, String)>[]) {
      for (final id in await _idsWhere(table, column, entityId)) {
        // A row that points at itself is the row being deleted.
        if (table == entityType && id == entityId) continue;

        targets.add((type: table, id: id));
      }
    }

    return targets;
  }

  /// Ids in [table] whose [column] holds [value].
  ///
  /// Raw SQL because the table and column are values here, not types. Both
  /// come from the constant maps above and never from a caller.
  Future<List<String>> _idsWhere(
    String table,
    String column,
    String value,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT id FROM $table WHERE $column = ?',
          variables: [Variable.withString(value)],
        )
        .get();

    return rows.map((r) => r.read<String>('id')).toList();
  }
}
