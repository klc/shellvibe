import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/restored_data.dart';
import '../../../../core/api/api_exception.dart';
import '../../../../core/sync/backup_scope_store.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../../core/sync/sync_journal.dart';
import '../../../../shared/database/app_database.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../account/presentation/notifiers/account_notifier.dart';
import '../../../billing/presentation/notifiers/entitlement_notifier.dart';
import '../../../settings/presentation/notifiers/backup_scope_notifier.dart';
import '../../data/cloud_backup_store.dart';
import '../../data/sync_operations_api.dart';

part 'sync_notifier.g.dart';

/// Why automatic sync is not running.
enum SyncBlocker {
  /// Switched off. The resting state, and the default.
  disabled,

  /// No account, or the plan does not include cloud backup.
  notEntitled,

  /// No passphrase on this device yet.
  notConfigured,

  /// No sync key: this vault has no backup carrying one.
  ///
  /// Not an error. The key cannot be invented -- every device has to hold the
  /// same one -- so the first backup taken after switching sync on is what
  /// creates it, and every other device learns it by opening a backup.
  needsBackup,
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

  final String? error;

  const SyncState({
    this.blocker = SyncBlocker.disabled,
    this.running = false,
    this.lastSyncAt,
    this.lastPushed = 0,
    this.lastPulled = 0,
    this.needsSnapshotRestore = false,
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

    final enabled = await ref.watch(autoSyncEnabledProvider.future);
    if (!enabled) {
      _stop();

      return const SyncState(blocker: SyncBlocker.disabled);
    }

    final entitlement = await ref.watch(entitlementProvider.future);

    if (!account.isSignedIn || !entitlement.hasCloudBackup) {
      _stop();

      return const SyncState(blocker: SyncBlocker.notEntitled);
    }

    final store = CloudBackupStore(
      storage: ref.watch(secureStorageServiceProvider),
    );

    if (await store.readPassphrase() == null) {
      _stop();

      return const SyncState(blocker: SyncBlocker.notConfigured);
    }

    final storedKey = await store.readSyncKey();
    if (storedKey == null) {
      _stop();

      // Nothing is broken. This vault simply has no backup carrying a sync
      // key yet, and taking one is what creates it.
      return const SyncState(blocker: SyncBlocker.needsBackup);
    }

    _engine = SyncEngine(
      db: db,
      journal: db.syncJournal!,
      api: SyncOperationsApi(
        client: ref.watch(accountProvider.notifier).apiClient,
      ),
      syncKey: SecretKey(base64.decode(storedKey)),
      scope: await ref.watch(backupScopeProvider(BackupTarget.autoSync).future),
    );

    _start(db);

    // A device that has just switched sync on is behind by everything that
    // happened before it did. Catching up is the first thing to do, and it
    // happens before anything local is sent.
    unawaited(syncNow(pullFirst: true));

    return const SyncState(blocker: null);
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
    _stop();

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

  void _stop() {
    _debounce?.cancel();
    _periodic?.cancel();
    unawaited(_changes?.cancel());
    _debounce = null;
    _periodic = null;
    _changes = null;
    _engine = null;
  }

  void _publish(SyncState Function(SyncState state) update) {
    final current = state.value;
    if (current == null) return;

    state = AsyncValue.data(update(current));
  }
}
