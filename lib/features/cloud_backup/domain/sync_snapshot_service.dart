import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/sync/e2ee_cloud_sync_service.dart';
import '../../../shared/database/app_database.dart';
import '../data/cloud_backup_api.dart';
import 'cloud_backup_service.dart';

/// A cold-start ground that was found and opened.
@immutable
final class SyncGround {
  /// The revision it was read from.
  final int revision;

  /// The device that wrote it, which breaks clock ties on the rows it
  /// restores.
  final String deviceId;

  /// The clock the snapshot was taken at, or null for one written before the
  /// clock was recorded.
  final int? syncClock;

  /// The sealed envelope, to hand to the importer.
  final String ciphertext;

  const SyncGround({
    required this.revision,
    required this.deviceId,
    required this.syncClock,
    required this.ciphertext,
  });
}

/// Why no ground could be read.
enum SyncGroundProblem {
  /// The sync vault is empty. The first device to switch sync on writes one.
  none,

  /// Revisions exist, but none of them carries everything automatic sync
  /// carries -- so starting from one would leave a category missing with
  /// nothing left to fill it in from.
  allPartial,

  /// The passphrase or recovery code does not open what is stored.
  cannotOpen,
}

/// How far the log may run past the ground before it is rewritten.
///
/// The ground and the log have to overlap. The server keeps operations for
/// ninety days, so a ground older than that window is one no device can bridge
/// to: it restores, then asks for operations that were pruned, and the gap
/// between them is data that is simply missing -- silently, because nothing in
/// that sequence fails.
///
/// Five hundred is a starting point rather than a measurement, chosen to be
/// far below what ninety days of operations comes to while still rare enough
/// that refreshing does not become a habit. `docs/sync_v3_plan.md` 12 keeps
/// this open.
const int kSyncGroundStaleOps = 500;

/// How old the ground may get before it is rewritten, whatever the log did.
///
/// A quiet account produces few operations, so the clock test alone would let
/// a ground sit until it fell out of the retention window without ever looking
/// stale.
const Duration kSyncGroundMaxAge = Duration(days: 7);

/// Reads and writes the vault automatic sync starts a new device from.
///
/// Separate from [CloudBackupService] in intent, not in machinery: it drives
/// one, pointed at the sync vault. Upload ids, size limits, conflict mapping
/// and checksum verification are the same problems with the same answers, and
/// a second implementation of them would be a second set of bugs.
///
/// What this class adds is the rules that make a snapshot a *ground*: it is
/// always written with [BackupScope.syncGround], it always carries the sync
/// key and the clock, and a revision that does not cover that scope is not
/// accepted as a starting point.
final class SyncSnapshotService {
  final CloudBackupService backups;

  /// Which ground this device last wrote or started from.
  ///
  /// Injected rather than read here: this class owns the rules about grounds,
  /// not where a device keeps its notes.
  final Future<({int revision, int clock})?> Function() readMark;
  final Future<void> Function({required int revision, required int clock})
  writeMark;

  const SyncSnapshotService({
    required this.backups,
    required this.readMark,
    required this.writeMark,
  });

  /// A service pointed at the sync vault.
  ///
  /// [readPendingUploadId] and [writePendingUploadId] must be a *different*
  /// pair from the backup vault's. One shared key would let a retry of a
  /// backup upload be answered with the sync vault's stored revision.
  factory SyncSnapshotService.over({
    required CloudBackupService backupService,
    required VaultTransport syncApi,
    required Future<String?> Function() readPendingUploadId,
    required Future<void> Function(String? uploadId) writePendingUploadId,
    required Future<({int revision, int clock})?> Function() readMark,
    required Future<void> Function({required int revision, required int clock})
    writeMark,
  }) => SyncSnapshotService(
    backups: CloudBackupService(
      api: syncApi,
      sync: backupService.sync,
      readPendingUploadId: readPendingUploadId,
      writePendingUploadId: writePendingUploadId,
      newUploadId: backupService.newUploadId,
    ),
    readMark: readMark,
    writeMark: writeMark,
  );

  Future<VaultHead> head() => backups.head();

  /// Writes this device's database as the ground others start from.
  ///
  /// Always the full sync scope, whatever this device has narrowed its own
  /// syncing to: a device that syncs only hosts still holds the rest, and a
  /// ground missing a category is one that no later snapshot or operation
  /// will fill in.
  Future<CloudBackupUploadResult> write({
    required AppDatabase db,
    required String passphrase,
    required String deviceId,
    required int maxSizeBytes,
    required Uint8List syncKey,
    String? recoveryCode,
    bool force = false,
  }) async {
    final state = await db.syncJournal?.readState();
    final clock = state?.lastSeenClock ?? 0;

    final result = await backups.upload(
      db: db,
      passphrase: passphrase,
      deviceId: deviceId,
      maxSizeBytes: maxSizeBytes,
      recoveryCode: recoveryCode,
      force: force,
      scope: BackupScope.syncGround,
      syncKey: syncKey,
      syncClock: clock,
    );

    if (result.succeeded) {
      await writeMark(revision: result.revision!, clock: clock);
    }

    return result;
  }

  /// Rewrites the ground when it has fallen too far behind the log.
  ///
  /// The two have to overlap. A device restores the ground and then asks for
  /// operations from the clock it recorded; if those were pruned, what sits
  /// between them is data no device can reach -- and nothing in that sequence
  /// fails, so nobody finds out.
  ///
  /// Only one device has to do this, so a conflict is success by another
  /// route: it means another device rewrote it first. Never forced --
  /// overwriting a ground another device has just written is the one move here
  /// that loses data.
  ///
  /// Returns true when this device wrote a new one.
  Future<bool> refreshIfStale({
    required AppDatabase db,
    required String passphrase,
    required String deviceId,
    required int maxSizeBytes,
    required Uint8List syncKey,
    String? recoveryCode,
    DateTime? now,
  }) async {
    final current = await head();

    // Nothing to refresh. The account has no ground, which is the joining
    // path's problem and not this one's.
    if (current.isEmpty) return false;

    final mark = await readMark();
    final at = now ?? DateTime.now();

    final tooOld =
        current.updatedAt != null &&
        at.difference(current.updatedAt!) > kSyncGroundMaxAge;

    var driftedTooFar = false;
    if (mark != null && mark.revision == current.currentRevision) {
      final state = await db.syncJournal?.readState();
      driftedTooFar =
          (state?.lastSeenClock ?? 0) - mark.clock > kSyncGroundStaleOps;
    }

    // A revision this device does not recognise means another one rewrote the
    // ground, and only it knows the clock that went in. Age still applies --
    // it comes from the server and every device reads the same number.
    if (!tooOld && !driftedTooFar) return false;

    final written = await write(
      db: db,
      passphrase: passphrase,
      deviceId: deviceId,
      maxSizeBytes: maxSizeBytes,
      syncKey: syncKey,
      recoveryCode: recoveryCode,
    );

    return written.succeeded;
  }

  /// The newest revision that covers the whole sync scope.
  ///
  /// Walks back rather than trusting the head. Every revision this service
  /// writes is complete, but the vault is addressable by any client and a
  /// partial one would otherwise become the ground a device starts from --
  /// which fails at restore time, on the device that can least afford it.
  ///
  /// Returns null and a [SyncGroundProblem] when there is nothing usable.
  Future<({SyncGround? ground, SyncGroundProblem? problem})> readGround({
    required String secret,
    BackupUnlockMethod unlockWith = BackupUnlockMethod.passphrase,
  }) async {
    final revisions = await backups.revisions();
    if (revisions.isEmpty) {
      return (ground: null, problem: SyncGroundProblem.none);
    }

    var sawSomethingUnopenable = false;

    for (final revision in revisions) {
      final opened = await backups.canOpen(
        revision: revision.revision,
        secret: secret,
        unlockWith: unlockWith,
      );

      if (opened == null) {
        sawSomethingUnopenable = true;
        continue;
      }

      final payload = jsonDecode(opened.payloadJson) as Map<String, dynamic>;
      final included = BackupScope.fromManifest(payload['included']);
      if (!included.coversSyncGround) continue;

      // Downloaded twice: once to decide, once to restore. The alternative is
      // holding every candidate's ciphertext in memory while walking back, and
      // a revision is up to the plan's whole size limit.
      final stored = await backups.api.revision(revision.revision);
      final ciphertext = stored.ciphertext;
      if (ciphertext == null || ciphertext.isEmpty) continue;

      return (
        ground: SyncGround(
          revision: revision.revision,
          deviceId: revision.deviceId,
          syncClock: payload['sync_clock'] as int?,
          ciphertext: ciphertext,
        ),
        problem: null,
      );
    }

    return (
      ground: null,
      problem: sawSomethingUnopenable
          ? SyncGroundProblem.cannotOpen
          : SyncGroundProblem.allPartial,
    );
  }

  /// Applies [ground] to [db].
  ///
  /// Merges: the importer upserts and never deletes, so the rows this device
  /// already holds survive a ground that does not mention them. That is what
  /// makes the order two devices switch sync on in stop mattering.
  Future<BackupImportResult> apply({
    required AppDatabase db,
    required SyncGround ground,
    required String secret,
    BackupUnlockMethod unlockWith = BackupUnlockMethod.passphrase,
  }) async {
    final result = await backups.sync.importEncryptedBackup(
      backupPackageJson: ground.ciphertext,
      db: db,
      masterPassword: secret,
      unlockWith: unlockWith,
      snapshotDeviceId: ground.deviceId,
    );

    // This device now stands on this ground, so staleness is measured from
    // here rather than from whatever it last wrote itself.
    await writeMark(revision: ground.revision, clock: ground.syncClock ?? 0);

    return result;
  }
}
