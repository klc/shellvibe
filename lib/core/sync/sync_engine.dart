import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../features/cloud_backup/data/sync_operations_api.dart';
import '../../shared/database/app_database.dart';
import '../api/api_exception.dart';
import '../crypto/encryption_engine.dart';
import 'backup_scope.dart';
import 'sync_aliases.dart';
import 'sync_journal.dart';
import 'sync_row_codec.dart';
import 'sync_row_writer.dart';

/// The log no longer reaches back to this device's cursor.
///
/// Not a failure to retry. The operations this device never saw have been
/// pruned, so the only way forward is the snapshot the server still holds --
/// which is the path the server's own `sync_cursor_expired` describes.
final class SyncCursorExpired implements Exception {
  const SyncCursorExpired();

  @override
  String toString() =>
      'SyncCursorExpired: restore from the snapshot and resume from its clock.';
}

/// What one sync pass did.
final class SyncResult {
  final int pushed;
  final int pulled;

  /// Operations that were pulled and deliberately not applied.
  final int skipped;

  /// References cleared because their target is not on this device.
  final int repaired;

  /// Operations that could not be decrypted with this device's sync key.
  ///
  /// Counted rather than only skipped. One of these is a stray operation from
  /// a vault that was re-keyed; a steady stream of them is the failure this
  /// number exists for -- two devices that each minted their own sync key,
  /// each pushing a log the other silently discards, with nothing on either
  /// screen saying so.
  final int unreadable;

  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.skipped = 0,
    this.repaired = 0,
    this.unreadable = 0,
  });

  bool get changedAnything => pushed > 0 || pulled > 0;
}

/// Sends local operations and applies remote ones.
///
/// Holds the sync key in memory only. It is recovered by opening the newest
/// envelope, which is why automatic sync requires a backup to exist at all.
final class SyncEngine {
  final AppDatabase db;
  final SyncJournal journal;
  final SyncOperationTransport api;
  final SyncAliases aliases;
  final EncryptionEngine crypto;

  /// Taken from the journal rather than passed separately.
  ///
  /// The journal stamps every version row with it, and the engine compares
  /// against those rows. Two sources for one identity is a mismatch waiting to
  /// happen, and it would show up as a tie-break that goes the wrong way on
  /// one device only.
  String get deviceId => journal.deviceId;

  /// Categories this device sends and applies.
  ///
  /// Both directions, deliberately. A one-way switch would leave "off"
  /// meaning something different depending on which device you asked.
  final BackupScope scope;

  SyncEngine({
    required this.db,
    required this.journal,
    required this.api,
    required SecretKey syncKey,
    this.scope = BackupScope.full,
    EncryptionEngine? crypto,
  }) : aliases = SyncAliases(syncKey: syncKey),
       crypto = crypto ?? EncryptionEngine(),
       _syncKey = syncKey;

  final SecretKey _syncKey;

  /// Tables each category owns, for filtering in both directions.
  static const Map<BackupCategory, List<String>> categoryTables = {
    BackupCategory.hosts: ['hosts'],
    BackupCategory.identities: ['identities', 'vault_env_vars'],
    BackupCategory.snippetsAndRunbooks: [
      'snippets',
      'runbooks',
      'runbook_steps',
    ],
    BackupCategory.portForwards: ['port_forward_rules'],
    BackupCategory.templates: ['templates', 'template_panes'],
    BackupCategory.bookmarks: ['bookmarks'],
  };

  /// Whether this device syncs [entityType].
  ///
  /// Workspaces and host groups are always in: everything else is filed under
  /// them, and a host arriving without its workspace is a row that cannot be
  /// written at all.
  ///
  /// A category that is off leaves a gap that does not close on its own. The
  /// cursor advances over the operations this device declined, so switching
  /// the category back on starts from that moment rather than replaying what
  /// it missed -- restoring a snapshot is what fills it in. Outgoing
  /// operations behave the other way round: they stay in the outbox, one per
  /// row, and go out whenever the category is switched back on.
  bool syncs(String entityType) {
    for (final entry in categoryTables.entries) {
      if (entry.value.contains(entityType)) return scope.contains(entry.key);
    }

    return true;
  }

  /// Sends everything waiting in the outbox.
  Future<int> push() async {
    final pending = (await journal.pending())
        .where((o) => syncs(o.entityType))
        .toList();

    if (pending.isEmpty) return 0;

    final operations = <SyncOperationDto>[];
    for (final operation in pending) {
      operations.add(
        SyncOperationDto(
          id: operation.id,
          deviceId: deviceId,
          logicalClock: operation.logicalClock,
          entityType: await aliases.forType(operation.entityType),
          entityId: await aliases.forEntity(
            entityType: operation.entityType,
            entityId: operation.entityId,
          ),
          operation: operation.operation,
          encryptedPayload: await _seal(operation),
        ),
      );
    }

    final count = await api.push(operations);

    // Only after the server has them. Clearing first would lose the
    // operations of a request that never arrived.
    await journal.clearSent(pending);

    return count;
  }

  /// Reads and applies everything after this device's cursor.
  ///
  /// Throws [SyncCursorExpired] when the log has been pruned past it.
  Future<SyncResult> pull({int maxPages = 20}) async {
    var pulled = 0;
    var skipped = 0;
    var repaired = 0;
    var unreadable = 0;

    for (var page = 0; page < maxPages; page++) {
      final state = await journal.readState();

      final SyncOperationPage batch;
      try {
        batch = await api.pull(
          sinceClock: state.pulledThroughClock,
          limit: SyncOperationsApi.defaultLimit,
        );
      } on ApiException catch (e) {
        if (e.isSyncCursorExpired) throw const SyncCursorExpired();
        rethrow;
      }

      if (batch.isEmpty) break;

      final outcome = await _apply(batch, sinceClock: state.pulledThroughClock);
      pulled += outcome.pulled;
      skipped += outcome.skipped;
      repaired += outcome.repaired;
      unreadable += outcome.unreadable;

      if (!batch.hasMore) break;
    }

    return SyncResult(
      pulled: pulled,
      skipped: skipped,
      repaired: repaired,
      unreadable: unreadable,
    );
  }

  /// One pass: send, then receive.
  ///
  /// Push first so this device's own changes carry a clock below anything it
  /// is about to learn, which keeps its edits from losing to operations it had
  /// not seen when it made them.
  Future<SyncResult> syncOnce() async {
    final pushed = await push();
    final pulledResult = await pull();

    return SyncResult(
      pushed: pushed,
      pulled: pulledResult.pulled,
      skipped: pulledResult.skipped,
      repaired: pulledResult.repaired,
      unreadable: pulledResult.unreadable,
    );
  }

  Future<SyncResult> _apply(
    SyncOperationPage batch, {
    required int sinceClock,
  }) async {
    final decoded = <_IncomingOperation>[];
    var unreadable = 0;

    for (final operation in batch.operations) {
      // This device's own operations come back on the next pull. Applying
      // them would be harmless but pointless, and it would move rows that
      // have changed since back to what they were when they were sent.
      if (operation.deviceId == deviceId) continue;

      final incoming = await _open(operation);
      if (incoming == null) {
        unreadable++;
        continue;
      }
      if (!syncs(incoming.entityType)) continue;

      decoded.add(incoming);
    }

    // Dependency order, so a host is written after the workspace it belongs
    // to rather than being skipped for a parent that arrives later in the
    // same batch.
    decoded.sort((a, b) {
      final byType = SyncRowCodec.syncableTypes
          .indexOf(a.entityType)
          .compareTo(SyncRowCodec.syncableTypes.indexOf(b.entityType));

      return byType != 0 ? byType : a.compareTo(b);
    });

    var applied = 0;
    var skipped = 0;
    var repaired = 0;

    await db.transaction(() async {
      // Self-references cannot be checked while the rows are still arriving.
      await db.customStatement('PRAGMA defer_foreign_keys = ON;');

      for (final incoming in decoded) {
        if (await _loses(incoming)) {
          skipped++;
          continue;
        }

        if (incoming.isDelete) {
          await SyncRowWriter.deleteRow(
            db,
            incoming.entityType,
            incoming.entityId,
          );
          await _recordVersion(incoming);
          applied++;
          continue;
        }

        final result = await SyncRowWriter.write(
          db,
          incoming.entityType,
          incoming.row!,
        );

        if (result.written) {
          await _recordVersion(incoming);
          applied++;
          repaired += result.clearedReferences.length;
        } else {
          skipped++;
        }
      }

      final cleared = await SyncRowWriter.clearDanglingSelfReferences(db);
      repaired += cleared.values.fold(0, (sum, n) => sum + n);

      // Inside the transaction, and only now. A cursor advanced before the
      // rows it accounts for are durable turns an interrupted sync into
      // permanent loss: the skipped operations are never offered again.
      //
      // The clock still moves to the top of the page whatever the cursor
      // does. Lamport: this device has *seen* everything the page carried,
      // and the next change it makes has to be ordered after it.
      await journal.observeClock(batch.maxClock);
      await journal.acknowledgePull(_cursorFor(batch, sinceClock));
    });

    return SyncResult(
      pulled: applied,
      skipped: skipped,
      repaired: repaired,
      unreadable: unreadable,
    );
  }

  /// How far to move the cursor after applying [batch].
  ///
  /// Two devices produce the same logical clock all the time -- the clock is
  /// a per-device counter, so both start at 1 -- and the server's cursor is
  /// exclusive. If a page ends in the middle of a clock, acknowledging that
  /// clock asks for everything *after* it next time and the rest of the tied
  /// operations are never offered again. Silently: nothing fails, the row
  /// simply never arrives.
  ///
  /// So a page with more behind it stops one clock short of its own top,
  /// which re-reads the tied operations on the next page. Applying is
  /// idempotent -- last-writer-wins against the version rows -- so re-reading
  /// them costs a little bandwidth and changes nothing.
  ///
  /// Held back only when the page carries more than one clock. A page that is
  /// entirely one clock would otherwise never move the cursor at all, and a
  /// device that cannot advance is worse off than one that skips a tie.
  static int _cursorFor(SyncOperationPage batch, int sinceClock) {
    final canHoldBack =
        batch.hasMore &&
        batch.operations.any((o) => o.logicalClock < batch.maxClock);

    final cursor = canHoldBack ? batch.maxClock - 1 : batch.maxClock;

    // Never backwards. A server that answers with a lower clock than this
    // device already acknowledged would otherwise make it replay the log.
    return cursor < sinceClock ? sinceClock : cursor;
  }

  /// Whether [incoming] loses to what this device already holds.
  ///
  /// Entity level last-writer-wins, ordered by `(clock, deviceId)`. The device
  /// id breaks the tie so two devices that produced the same clock offline
  /// still reach the same answer -- determinism is the only thing a merge rule
  /// has to provide, and without the tie-break two devices that edited the
  /// same row would each adopt the other's value and swap rather than
  /// converge.
  ///
  /// The comparison is against the version row, not the outbox. An operation
  /// that has been sent is cleared from the outbox, and a device that went by
  /// the outbox alone would then have nothing to defend its own row with.
  Future<bool> _loses(_IncomingOperation incoming) async {
    final version = await journal.versionFor(
      entityType: incoming.entityType,
      entityId: incoming.entityId,
    );

    if (version != null) {
      if (version.logicalClock > incoming.logicalClock) return true;
      if (version.logicalClock == incoming.logicalClock) {
        return version.deviceId.compareTo(incoming.deviceId) > 0;
      }

      return false;
    }

    // An upsert for a row this device deleted before versions were kept for
    // it. Without this a delete and a rewrite processed out of order
    // resurrect the row -- the failure that turns up in every write-up of a
    // home-grown sync.
    if (!incoming.isDelete) {
      final tombstone = await journal.tombstoneFor(
        entityType: incoming.entityType,
        entityId: incoming.entityId,
      );

      if (tombstone != null && tombstone.logicalClock > incoming.logicalClock) {
        return true;
      }
    }

    return false;
  }

  /// Moves the row's version to where the applied operation put it.
  ///
  /// Without this the next pull would compare against a version that predates
  /// what this device just wrote, and an older operation could overwrite it.
  Future<void> _recordVersion(_IncomingOperation incoming) =>
      journal.setVersion(
        entityType: incoming.entityType,
        entityId: incoming.entityId,
        logicalClock: incoming.logicalClock,
        deviceId: incoming.deviceId,
      );

  /// Seals one outgoing operation.
  ///
  /// The real table and id travel **inside** the ciphertext. The server sees
  /// only their HMAC aliases, which cannot be inverted, so without this the
  /// receiving device would have no way to know what a pulled operation is
  /// about.
  Future<String> _seal(PendingOperation operation) async {
    final body = <String, Object?>{
      't': operation.entityType,
      'i': operation.entityId,
      if (operation.payload != null)
        'r': jsonDecode(operation.payload!) as Map<String, dynamic>,
    };

    return crypto.encrypt(plaintext: jsonEncode(body), secretKey: _syncKey);
  }

  /// Opens one pulled operation, or returns null when it cannot be trusted.
  Future<_IncomingOperation?> _open(SyncOperationDto operation) async {
    final Map<String, Object?> body;
    try {
      body =
          jsonDecode(
                await crypto.decrypt(
                  encryptedBase64: operation.encryptedPayload,
                  secretKey: _syncKey,
                ),
              )
              as Map<String, Object?>;
    } on Object {
      // Written under a different sync key, or tampered with. Either way this
      // device cannot act on it, and guessing would be worse than skipping.
      return null;
    }

    final entityType = body['t'] as String?;
    final entityId = body['i'] as String?;
    if (entityType == null || entityId == null) return null;
    if (!SyncRowCodec.syncableTypes.contains(entityType)) return null;

    // The alias is recomputed from what was inside the ciphertext. The server
    // cannot forge one without the sync key, so a mismatch means the payload
    // and the row it claims to be about do not belong together.
    final expectedId = await aliases.forEntity(
      entityType: entityType,
      entityId: entityId,
    );
    if (expectedId != operation.entityId) return null;

    return _IncomingOperation(
      entityType: entityType,
      entityId: entityId,
      deviceId: operation.deviceId,
      logicalClock: operation.logicalClock,
      isDelete: operation.isDelete,
      row: body['r'] as Map<String, Object?>?,
    );
  }
}

/// A pulled operation with its real identity recovered.
final class _IncomingOperation implements Comparable<_IncomingOperation> {
  final String entityType;
  final String entityId;
  final String deviceId;
  final int logicalClock;
  final bool isDelete;
  final Map<String, Object?>? row;

  const _IncomingOperation({
    required this.entityType,
    required this.entityId,
    required this.deviceId,
    required this.logicalClock,
    required this.isDelete,
    required this.row,
  });

  @override
  int compareTo(_IncomingOperation other) {
    final byClock = logicalClock.compareTo(other.logicalClock);

    return byClock != 0 ? byClock : deviceId.compareTo(other.deviceId);
  }
}
