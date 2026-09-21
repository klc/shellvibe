import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/restored_data.dart';
import '../../../../core/api/api_exception.dart';
import '../../../../core/sync/backup_scope_store.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../../core/sync/sync_journal.dart';
import '../../../../shared/database/app_database.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../account/presentation/notifiers/account_notifier.dart';
import '../../../billing/presentation/notifiers/entitlement_notifier.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../../settings/presentation/notifiers/backup_scope_notifier.dart';
import '../../data/cloud_backup_api.dart';
import '../../data/cloud_backup_store.dart';
import '../../data/sync_operations_api.dart';
import '../../domain/cloud_backup_service.dart';
import '../../domain/sync_join_service.dart';
import '../../domain/sync_snapshot_service.dart';

part 'sync_notifier.g.dart';

/// Why automatic sync is not running.
enum SyncBlocker {
  /// Switched off. The resting state, and the default.
  disabled,

  /// No account on this device. Sync itself is free; it just has nowhere to
  /// sync to without one.
  signedOut,

  /// No passphrase on this device yet.
  notConfigured,

  /// This account holds snapshots, but none covers everything sync carries.
  ///
  /// Starting from one would leave a category missing that nothing later
  /// fills in, so the user is asked for a complete backup instead of being
  /// quietly given part of their data.
  noCompleteGround,

  /// The stored passphrase does not open this account's sync snapshot.
  wrongPassphrase,
}

/// What automatic sync is doing.
@immutable
final class SyncState {
  final SyncBlocker? blocker;
  final bool running;

  /// When the last pass finished, whether or not it changed anything.
  final DateTime? lastSyncAt;

  /// Operations sent and applied in the last pass.
  final int lastPushed;
  final int lastPulled;

  /// Set when the log no longer reaches this device's cursor, which is asking
  /// for a restore rather than a retry.
  final bool needsSnapshotRestore;

  /// What joining this account did, the one time it ran.
  ///
  /// Kept rather than shown and dropped: the join can finish while the screen
  /// that would have reported it is closed, and "sixty hosts sent, two
  /// arrived" is the sentence that tells the user the switch did something.
  final SyncJoinResult? lastJoin;

  final String? error;

  const SyncState({
    this.blocker = SyncBlocker.disabled,
    this.running = false,
    this.lastSyncAt,
    this.lastPushed = 0,
    this.lastPulled = 0,
    this.needsSnapshotRestore = false,
    this.lastJoin,
    this.error,
  });

  bool get isActive => blocker == null;

  SyncState copyWith({
    SyncBlocker? blocker,
    bool? running,
    DateTime? lastSyncAt,
    int? lastPushed,
    int? lastPulled,
    bool? needsSnapshotRestore,
    SyncJoinResult? lastJoin,
    String? error,
    bool clearBlocker = false,
    bool clearError = false,
  }) => SyncState(
    blocker: clearBlocker ? null : (blocker ?? this.blocker),
    running: running ?? this.running,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    lastPushed: lastPushed ?? this.lastPushed,
    lastPulled: lastPulled ?? this.lastPulled,
    needsSnapshotRestore: needsSnapshotRestore ?? this.needsSnapshotRestore,
    lastJoin: lastJoin ?? this.lastJoin,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Runs automatic sync.
///
/// Rebuilds when the account, the entitlement or the switch changes, so
/// signing out or turning it off stops it without anything having to listen.
///
/// `keepAlive` because it owns timers: a disposed instance would leave them
/// firing into nothing.
@Riverpod(keepAlive: true)
class SyncNotifier extends _$SyncNotifier {
  SyncEngine? _engine;
  SyncJoinService? _join;
  bool _joinStarted = false;
  SyncSnapshotService? _ground;
  String? _deviceId;
  String? _passphrase;
  Uint8List? _syncKey;
  int _maxSizeBytes = 0;
  Timer? _debounce;
  Timer? _periodic;
  StreamSubscription<void>? _changes;

  /// One pass at a time. Two overlapping passes would push the same
  /// operations twice and race each other's cursor writes.
  Future<void> _inFlight = Future<void>.value();

  /// How long to wait after a change before sending.
  ///
  /// The write limit is 30 requests a minute, so a request per keystroke is
  /// not affordable. Waiting also lets the edits of one form collapse into a
  /// single operation per row before anything leaves the device.
  static const Duration debounce = Duration(seconds: 5);

  /// How often to look for what other devices have sent.
  ///
  /// There is no push channel for the operation log, so this is a poll. Five
  /// minutes is the compromise the design note settled on: often enough to
  /// feel automatic, rare enough not to spend the read budget.
  static const Duration pollInterval = Duration(minutes: 5);

  @override
  Future<SyncState> build() async {
    ref.onDispose(_stop);

    final db = ref.watch(appDatabaseProvider);
    final account = await ref.watch(accountProvider.future);

    // The journal is attached whether or not sync is running. A change made
    // while it is switched off still has to be recorded, or switching it on
    // would start from an empty outbox and the edits made in between would
    // never reach any other device -- silently, because nothing fails.
    db.syncJournal = SyncJournal(
      db: db,
      deviceId: account.session?.deviceId ?? 'local',
    );

    // The trash holds the body of every deleted row so a mistaken delete can
    // be taken back, which means a secret stays on disk for the length of the
    // retention window. Nothing else runs the clock down, so without this the
    // window never closes and the promise the delete confirmation makes --
    // thirty days -- is not kept.
    unawaited(db.syncJournal!.purgeTrash());

    final enabled = await ref.watch(autoSyncEnabledProvider.future);
    if (!enabled) {
      _stop();

      return const SyncState(blocker: SyncBlocker.disabled);
    }

    if (!account.isSignedIn) {
      _stop();

      return const SyncState(blocker: SyncBlocker.signedOut);
    }

    // Read for its limits, not for permission: sync is free, and the upload
    // size the server will accept is the one thing here the client cannot
    // know on its own.
    final entitlement = await ref.watch(entitlementProvider.future);

    final store = CloudBackupStore(
      storage: ref.watch(secureStorageServiceProvider),
    );

    if (await store.readPassphrase() == null) {
      _stop();

      return const SyncState(blocker: SyncBlocker.notConfigured);
    }

    final passphrase = (await store.readPassphrase())!;
    final client = ref.watch(accountProvider.notifier).apiClient;

    final ground = SyncSnapshotService.over(
      backupService: CloudBackupService(
        api: CloudBackupApi(client: client),
        sync: ref.watch(e2eeCloudSyncServiceProvider),
        readPendingUploadId: store.readPendingUploadId,
        writePendingUploadId: store.writePendingUploadId,
        newUploadId: const Uuid().v4,
      ),
      syncApi: CloudBackupApi(client: client, kind: VaultKind.sync),
      readPendingUploadId: store.readPendingSyncUploadId,
      writePendingUploadId: store.writePendingSyncUploadId,
      readMark: store.readGroundMark,
      writeMark: store.writeGroundMark,
    );

    final Uint8List syncKey;
    try {
      syncKey = await _resolveSyncKey(store, ground, passphrase);
    } on _NoCompleteGround {
      _stop();

      return const SyncState(blocker: SyncBlocker.noCompleteGround);
    } on _WrongPassphrase {
      _stop();

      return const SyncState(blocker: SyncBlocker.wrongPassphrase);
    }

    _deviceId = account.session!.deviceId;
    _maxSizeBytes = entitlement.entitlement.limits.maxBackupSizeBytes;
    _passphrase = passphrase;
    _syncKey = syncKey;
    _ground = ground;

    _engine = SyncEngine(
      db: db,
      journal: db.syncJournal!,
      api: SyncOperationsApi(client: client),
      syncKey: SecretKey(syncKey),
      scope: await ref.watch(backupScopeProvider(BackupTarget.autoSync).future),
    );

    _join = SyncJoinService(
      db: db,
      journal: db.syncJournal!,
      ground: ground,
      engine: _engine!,
    );

    _start(db);

    // Joining comes before anything else, and is safe to run every start: a
    // device that has finished returns at once, and one that was closed
    // halfway through finishes rather than calling itself done.
    //
    // Started from `listenSelf` rather than from here, and that is the whole
    // point of it: fired from inside `build` it runs while `state` is still
    // loading, and every `_publish` it makes is dropped because there is no
    // state to update yet. The join's result and, worse, its failure both
    // land on the floor, and the screen keeps showing the "watching for
    // changes" this method is about to return -- a sync that reports itself
    // healthy while nothing has happened at all.
    // On the event queue, not here: `build`'s own return value is assigned
    // after it completes, so anything published from inside it is overwritten
    // a moment later even when it is not dropped outright.
    Future(() => unawaited(_startJoinOnce()));

    return const SyncState(blocker: null);
  }

  /// Finds the key every device in this account has to share.
  ///
  /// It cannot be derived or invented. Two devices that each minted their own
  /// would seal operations the other silently skips -- nothing would fail, and
  /// neither would ever see the other's work. So: what this device already
  /// holds, or what the account's ground carries, or -- only for an account
  /// with no ground at all -- a new one.
  Future<Uint8List> _resolveSyncKey(
    CloudBackupStore store,
    SyncSnapshotService ground,
    String passphrase,
  ) async {
    final stored = await store.readSyncKey();
    if (stored != null) return base64.decode(stored);

    final found = await ground.readGround(secret: passphrase);

    if (found.problem == SyncGroundProblem.cannotOpen) {
      throw const _WrongPassphrase();
    }
    if (found.problem == SyncGroundProblem.allPartial) {
      throw const _NoCompleteGround();
    }

    final carried = found.ground?.syncKey;
    if (carried != null) {
      await store.adoptSyncKey(carried);

      return Uint8List.fromList(await carried.extractBytes());
    }

    // An account with no ground, or one whose ground predates the key. This
    // device mints it and the first ground it writes carries it onward.
    return (await store.syncKeyForUpload(autoSyncEnabled: true))!;
  }

  /// Runs the join the first time this build publishes a state.
  ///
  /// `listenSelf` fires on every publish, including the ones the join itself
  /// makes, so the guard is what keeps one join from starting another.
  Future<void> _startJoinOnce() async {
    if (_joinStarted || _join == null) return;
    _joinStarted = true;

    await _joinThenSync();
  }

  /// Joins, then runs a first pass.
  Future<void> _joinThenSync() async {
    final join = _join;
    if (join == null) return;

    try {
      final result = await join.join(
        secret: _passphrase!,
        deviceId: _deviceId!,
        maxSizeBytes: _maxSizeBytes,
        syncKey: _syncKey!,
      );

      if (!result.succeeded) {
        debugPrint('[Sync] join refused: ${result.problem} ${result.message}');
        _publish((s) => s.copyWith(error: result.message));

        return;
      }

      debugPrint(
        '[Sync] joined: applied=${result.applied} seeded=${result.seeded} '
        'pushed=${result.pushed} firstGround=${result.wroteFirstGround}',
      );

      if (result.applied > 0) invalidateRestoredData(ref);

      _publish(
        (s) => s.copyWith(
          lastJoin: result,
          lastSyncAt: DateTime.now(),
          lastPushed: result.pushed,
          lastPulled: result.applied,
        ),
      );
    } on Object catch (e, stackTrace) {
      debugPrint('[Sync] join failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      _publish((s) => s.copyWith(error: '$e'));

      return;
    }

    await syncNow(pullFirst: true);

    // The ground and the log have to overlap, and only one device has to keep
    // them that way. A conflict here means another got there first.
    unawaited(_refreshGround());
  }

  Future<void> _refreshGround() async {
    final ground = _ground;
    if (ground == null) return;

    try {
      await ground.refreshIfStale(
        db: ref.read(appDatabaseProvider),
        passphrase: _passphrase!,
        deviceId: _deviceId!,
        maxSizeBytes: _maxSizeBytes,
        syncKey: _syncKey!,
      );
    } on Object catch (e) {
      // Housekeeping. A device that cannot refresh the ground today syncs
      // perfectly well; another one will, and this one tries again next start.
      debugPrint('[Sync] ground refresh skipped: $e');
    }
  }

  /// Runs one pass now.
  ///
  /// [pullFirst] inverts the usual order for a device that is joining: it has
  /// nothing worth sending until it knows what is already there, and sending
  /// first is how a fresh install once wrote its empty database over a good
  /// backup.
  Future<void> syncNow({bool pullFirst = false}) {
    final engine = _engine;
    if (engine == null) return Future.value();

    _inFlight = _inFlight.then((_) async {
      _publish((s) => s.copyWith(running: true, clearError: true));

      try {
        final result = pullFirst
            ? await _pullThenPush(engine)
            : await engine.syncOnce();

        if (result.pulled > 0) {
          // The operations wrote straight to the database, so every list
          // notifier is still holding what it read at startup.
          invalidateRestoredData(ref);
        }

        _publish(
          (s) => s.copyWith(
            running: false,
            lastSyncAt: DateTime.now(),
            lastPushed: result.pushed,
            lastPulled: result.pulled,
            needsSnapshotRestore: false,
          ),
        );
      } on SyncCursorExpired {
        // Not a retry. The operations this device never saw are gone, and the
        // only way forward is the snapshot the server still holds.
        _publish(
          (s) => s.copyWith(
            running: false,
            needsSnapshotRestore: true,
            error:
                'This device is too far behind to catch up from the change '
                'log. Restore the latest backup to resume.',
          ),
        );
      } on ApiException catch (e) {
        _publish((s) => s.copyWith(running: false, error: e.message));
      } on Object catch (e) {
        _publish((s) => s.copyWith(running: false, error: '$e'));
      }
    });

    return _inFlight;
  }

  Future<SyncResult> _pullThenPush(SyncEngine engine) async {
    final pulled = await engine.pull();
    final pushed = await engine.push();

    return SyncResult(
      pushed: pushed,
      pulled: pulled.pulled,
      skipped: pulled.skipped,
      repaired: pulled.repaired,
    );
  }

  void _start(AppDatabase db) {
    // Timers only. This runs right after `build` has constructed the engine
    // and the join service, so tearing those down here would throw away what
    // it was called to start -- which is what it used to do.
    _stopTimers();

    _periodic = Timer.periodic(pollInterval, (_) => syncNow());

    // Every local change lands in the outbox, so watching that table is the
    // one signal that covers every write path without each of them having to
    // remember to announce itself.
    _changes = db
        .tableUpdates(TableUpdateQuery.onTable(db.pendingOperations))
        .listen((_) {
          _debounce?.cancel();
          _debounce = Timer(debounce, syncNow);
        });
  }

  /// Cancels what is scheduled, and leaves the engine alone.
  ///
  /// Split from [_stop] because they answer different questions. Restarting
  /// the timers is not the same as shutting sync down, and a single method
  /// doing both meant every start immediately discarded the engine it was
  /// starting for. Nothing failed: `syncNow` simply returned at its null
  /// check, so the debounce, the poll and the foreground pass all ran and
  /// did nothing, forever.
  void _stopTimers() {
    _debounce?.cancel();
    _periodic?.cancel();
    unawaited(_changes?.cancel());
    _debounce = null;
    _periodic = null;
    _changes = null;
  }

  /// Shuts sync down: nothing scheduled, nothing to run.
  void _stop() {
    _stopTimers();

    _engine = null;
    _join = null;
    _ground = null;
    _joinStarted = false;
  }

  /// The state as this notifier last knew it.
  ///
  /// `state.value` is null until `build` finishes, and the old version of
  /// [_publish] returned early in that window. That is how a join that failed
  /// before anyone opened the screen came to report itself as healthy: the
  /// error was written to a state that did not exist yet. Keeping a copy means
  /// a late update lands on the right thing rather than on nothing.
  SyncState _current = const SyncState(blocker: SyncBlocker.disabled);

  void _publish(SyncState Function(SyncState state) update) {
    _current = update(state.value ?? _current);

    state = AsyncValue.data(_current);
  }
}

/// The account's snapshots are all narrower than sync carries.
final class _NoCompleteGround implements Exception {
  const _NoCompleteGround();
}

/// The stored passphrase does not open the account's ground.
final class _WrongPassphrase implements Exception {
  const _WrongPassphrase();
}
