import 'package:flutter/foundation.dart';

import '../../../core/sync/e2ee_cloud_sync_service.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_journal.dart';
import '../../../features/vault/data/vault_key_service.dart';
import '../../../shared/database/app_database.dart';
import 'sync_snapshot_service.dart';

/// Why a join could not be completed.
enum SyncJoinProblem {
  /// The account holds snapshots, but none covers everything automatic sync
  /// carries. Starting from one would leave a category missing that nothing
  /// later fills in, so the user is asked for a complete backup instead.
  noCompleteGround,

  /// The passphrase or recovery code does not open what is stored.
  cannotOpen,

  /// The ground could not be written: too large, refused, or unreachable. The
  /// message says which.
  cannotWriteGround,

  /// The vault is locked, so identity secrets cannot be rewrapped.
  vaultLocked,
}

/// What joining did, in the numbers the user is owed.
@immutable
final class SyncJoinResult {
  /// Rows the ground brought to this device.
  final int applied;

  /// Rows this device queued because nothing else had them.
  final int seeded;

  /// Operations actually sent.
  final int pushed;

  /// True when this device wrote the first ground for the account.
  final bool wroteFirstGround;

  /// True when this device rewrote the ground after seeding.
  final bool refreshedGround;

  /// References cleared because their target is on neither side.
  final int repaired;

  final SyncJoinProblem? problem;
  final String? message;

  const SyncJoinResult({
    this.applied = 0,
    this.seeded = 0,
    this.pushed = 0,
    this.wroteFirstGround = false,
    this.refreshedGround = false,
    this.repaired = 0,
    this.problem,
    this.message,
  });

  const SyncJoinResult.failed({required this.problem, required this.message})
    : applied = 0,
      seeded = 0,
      pushed = 0,
      wroteFirstGround = false,
      refreshedGround = false,
      repaired = 0;

  bool get succeeded => problem == null;
}

/// Brings a device into an account's automatic sync.
///
/// The rule the whole thing rests on: **a joining device never replaces what
/// it holds.** It merges the ground in, queues whatever the ground did not
/// carry, sends that, and rewrites the ground. There is no step that empties a
/// table, so which device switched sync on first does not decide whose data
/// survives -- a phone with two hosts joining a desktop with sixty ends at
/// sixty-two either way round.
///
/// The worst case is a duplicate row, when the same server was typed by hand
/// on two devices and carries two ids. That is the trade: a visible duplicate
/// the user can delete, rather than an invisible loss they cannot.
final class SyncJoinService {
  final AppDatabase db;
  final SyncJournal journal;
  final SyncSnapshotService ground;
  final SyncEngine engine;

  const SyncJoinService({
    required this.db,
    required this.journal,
    required this.ground,
    required this.engine,
  });

  /// Runs the join, or resumes one that was interrupted.
  ///
  /// Safe to call on every start: a device that has finished returns
  /// immediately, and a device that was closed halfway through picks up where
  /// it stopped. That resumption is the point of storing the state at all --
  /// the alternative is a device that believes it joined while the rows it
  /// never sent sit on its disk, with nothing reporting a problem.
  Future<SyncJoinResult> join({
    required String secret,
    required String deviceId,
    required int maxSizeBytes,
    required Uint8List syncKey,
    String? recoveryCode,
    BackupUnlockMethod unlockWith = BackupUnlockMethod.passphrase,
  }) async {
    final state = await journal.readJoinState();
    if (state == SyncJoinState.done) return const SyncJoinResult();

    if (state == SyncJoinState.applied) {
      // The ground is already merged in and the rows are already queued. Only
      // the sending half is left.
      return _finish(
        seeded: (await journal.pending()).length,
        applied: 0,
        repaired: 0,
        secret: secret,
        deviceId: deviceId,
        maxSizeBytes: maxSizeBytes,
        syncKey: syncKey,
        recoveryCode: recoveryCode,
      );
    }

    final found = await ground.readGround(
      secret: secret,
      unlockWith: unlockWith,
    );

    if (found.problem == SyncGroundProblem.cannotOpen) {
      return const SyncJoinResult.failed(
        problem: SyncJoinProblem.cannotOpen,
        message:
            'The passphrase does not open this account\'s sync snapshot. '
            'Use the passphrase from a device that is already syncing.',
      );
    }

    if (found.problem == SyncGroundProblem.allPartial) {
      return const SyncJoinResult.failed(
        problem: SyncJoinProblem.noCompleteGround,
        message:
            'This account has no complete snapshot to start from. Take a full '
            'backup on a device that already has your data, then try again.',
      );
    }

    if (found.ground == null) {
      // An empty account. This device writes the ground others will start
      // from, and there is nobody to send operations to yet.
      return _writeFirstGround(
        secret: secret,
        deviceId: deviceId,
        maxSizeBytes: maxSizeBytes,
        syncKey: syncKey,
        recoveryCode: recoveryCode,
      );
    }

    final int applied;
    final int seeded;
    final int repaired;

    try {
      // One transaction, deliberately. A crash between merging the ground and
      // queueing this device's rows leaves a device whose clocks say it has
      // joined and whose outbox is empty -- and the rows it was supposed to
      // contribute never go anywhere, silently.
      final outcome = await db.transaction(() async {
        final result = await ground.apply(
          db: db,
          ground: found.ground!,
          secret: secret,
          unlockWith: unlockWith,
        );

        // What the ground brought, counted from the versions the restore
        // stamped rather than from the importer, which does not count as it
        // goes. Rows this device already held are in here too -- the ground
        // overwrote them, so they now stand where it says.
        final brought = result.syncClock == null
            ? 0
            : await journal.countVersionsAt(
                logicalClock: result.syncClock!,
                deviceId: found.ground!.deviceId,
              );

        final queued = await journal.seedUnversioned();
        await journal.writeJoinState(SyncJoinState.applied);

        return (
          applied: brought,
          seeded: queued,
          repaired: result.repairs.total,
        );
      });

      applied = outcome.applied;
      seeded = outcome.seeded;
      repaired = outcome.repaired;
    } on VaultLockedException {
      // Identity secrets are rewrapped under this device's key as they land,
      // which cannot happen behind a locked vault. Nothing was written: the
      // importer resolves the key before opening its transaction.
      return const SyncJoinResult.failed(
        problem: SyncJoinProblem.vaultLocked,
        message:
            'Unlock the vault to finish joining sync. Nothing was changed.',
      );
    }

    return _finish(
      applied: applied,
      seeded: seeded,
      repaired: repaired,
      secret: secret,
      deviceId: deviceId,
      maxSizeBytes: maxSizeBytes,
      syncKey: syncKey,
      recoveryCode: recoveryCode,
    );
  }

  /// Sends what the join queued, then refreshes the ground.
  Future<SyncJoinResult> _finish({
    required int applied,
    required int seeded,
    required int repaired,
    required String secret,
    required String deviceId,
    required int maxSizeBytes,
    required Uint8List syncKey,
    String? recoveryCode,
  }) async {
    final pushed = await engine.push();

    // The ground is still the one this device started from, and it does not
    // mention any of the rows just sent. Left alone, it stays the starting
    // point until the log is pruned past it -- and then a third device
    // restores it, misses everything this device contributed, and is not told.
    var refreshed = false;
    if (seeded > 0) {
      final written = await ground.write(
        db: db,
        passphrase: secret,
        deviceId: deviceId,
        maxSizeBytes: maxSizeBytes,
        syncKey: syncKey,
        recoveryCode: recoveryCode,
      );

      // A conflict here means another device refreshed it first, which is the
      // same outcome. Never forced: overwriting a ground another device just
      // wrote is the one move that can lose data.
      refreshed = written.succeeded;
    }

    await journal.writeJoinState(SyncJoinState.done);

    return SyncJoinResult(
      applied: applied,
      seeded: seeded,
      pushed: pushed,
      refreshedGround: refreshed,
      repaired: repaired,
    );
  }

  Future<SyncJoinResult> _writeFirstGround({
    required String secret,
    required String deviceId,
    required int maxSizeBytes,
    required Uint8List syncKey,
    String? recoveryCode,
  }) async {
    final written = await ground.write(
      db: db,
      passphrase: secret,
      deviceId: deviceId,
      maxSizeBytes: maxSizeBytes,
      syncKey: syncKey,
      recoveryCode: recoveryCode,
    );

    if (!written.succeeded) {
      return SyncJoinResult.failed(
        problem: SyncJoinProblem.cannotWriteGround,
        message: written.message ?? 'The sync snapshot could not be written.',
      );
    }

    // Versions, but nothing queued: the rows are already in the ground every
    // other device will start from, so sending them would tell nobody
    // anything. The versions still matter -- a row standing at no clock loses
    // to any operation that mentions it, however old.
    final stamped = await db.transaction(() async {
      final count = await journal.seedUnversioned(queue: false);
      await journal.writeJoinState(SyncJoinState.done);

      return count;
    });

    return SyncJoinResult(seeded: stamped, wroteFirstGround: true);
  }
}
