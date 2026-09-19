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

  /// Runs [write], which deletes the row, and records the delete.
  ///
  /// The body is read before [write] runs: after the delete there is nothing
  /// left to keep, and the body is what makes the delete undoable.
  Future<T> delete<T>({
    required String entityType,
    required String entityId,
    required Future<T> Function() write,
  }) => db.transaction(() async {
    final body = await SyncRowCodec.read(db, entityType, entityId);

    final result = await write();

    // The row was not there to begin with. Recording a delete for it would
    // put a tombstone in the way of an `upsert` that may still be in flight
    // from another device.
    if (body == null) return result;

    final clock = await _nextClock();

    await _write(
      entityType: entityType,
      entityId: entityId,
      operation: 'delete',
      payload: null,
      before: jsonEncode(body),
      clock: clock,
    );

    await db
        .into(db.syncTombstones)
        .insertOnConflictUpdate(
          SyncTombstonesCompanion.insert(
            entityType: entityType,
            entityId: entityId,
            body: Value(jsonEncode(body)),
            logicalClock: clock,
            deletedAt: DateTime.now(),
          ),
        );

    return result;
  });

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
}
