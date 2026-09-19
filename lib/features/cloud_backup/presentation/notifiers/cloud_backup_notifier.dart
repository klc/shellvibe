import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/restored_data.dart';
import '../../../../core/api/api_exception.dart';
import '../../../../core/sync/backup_scope_store.dart';
import '../../../../core/sync/e2ee_cloud_sync_service.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../account/presentation/notifiers/account_notifier.dart';
import '../../../billing/presentation/notifiers/entitlement_notifier.dart';
import '../../../settings/presentation/notifiers/settings_notifier.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../data/cloud_backup_api.dart';
import '../../data/cloud_backup_store.dart';
import '../../domain/cloud_backup_service.dart';

part 'cloud_backup_notifier.g.dart';

/// Why the cloud backup surface is not usable right now.
enum CloudBackupBlocker {
  /// No account on this device.
  signedOut,

  /// Signed in, but the plan does not include cloud backup.
  notEntitled,

  /// Entitled, the account has no backup yet, and this device has no
  /// passphrase: a genuine first-time setup.
  notConfigured,

  /// Entitled, this device has no passphrase, but the account already has a
  /// backup written by another device.
  ///
  /// Distinct from [notConfigured] because the two need opposite actions. A
  /// second device must be asked for the passphrase that already exists, not
  /// invited to invent a new one -- inventing one there produced a backup the
  /// first device could not open, and uploaded it over the good one.
  needsExistingPassphrase,
}

/// Immutable cloud backup state.
@immutable
final class CloudBackupState {
  /// Null when cloud backup is ready to use.
  final CloudBackupBlocker? blocker;

  /// What the server holds, when it has been read.
  final VaultHead? head;

  /// Revision metadata, newest first. Loaded on demand.
  final List<BackupRevision> revisions;

  /// The revision this device last wrote or restored.
  final int? lastKnownRevision;

  /// True while an upload, restore or delete is running.
  final bool busy;

  /// One sentence about the last action, success or failure.
  final String? message;

  /// True when [message] describes a failure.
  final bool messageIsError;

  /// Set when the last upload lost a race, so the UI can offer to overwrite.
  final int? conflictingServerRevision;

  /// True when this device holds the passphrase but not the recovery code.
  ///
  /// Backups written here cannot be opened with the recovery code, so the UI
  /// has to say so rather than let the user keep believing the code covers
  /// everything.
  final bool recoveryCodeMissing;

  /// When this device last wrote a backup that held everything, if ever.
  final DateTime? lastFullBackupAt;

  const CloudBackupState({
    this.blocker,
    this.head,
    this.revisions = const [],
    this.lastKnownRevision,
    this.busy = false,
    this.message,
    this.messageIsError = false,
    this.conflictingServerRevision,
    this.recoveryCodeMissing = false,
    this.lastFullBackupAt,
  });

  bool get isReady => blocker == null;

  /// How long ago the last complete backup was, or null when there has never
  /// been one from this device.
  Duration? get sinceLastFullBackup {
    final at = lastFullBackupAt;

    return at == null ? null : DateTime.now().difference(at);
  }

  /// True when the server holds a revision this device has not seen.
  bool get serverIsAhead {
    final serverRevision = head?.currentRevision;
    if (serverRevision == null || serverRevision == 0) return false;

    return serverRevision != lastKnownRevision;
  }

  CloudBackupState copyWith({
    CloudBackupBlocker? blocker,
    VaultHead? head,
    List<BackupRevision>? revisions,
    int? lastKnownRevision,
    bool? busy,
    String? message,
    bool? messageIsError,
    int? conflictingServerRevision,
    bool? recoveryCodeMissing,
    DateTime? lastFullBackupAt,
    bool clearBlocker = false,
    bool clearMessage = false,
    bool clearConflict = false,
  }) => CloudBackupState(
    blocker: clearBlocker ? null : (blocker ?? this.blocker),
    head: head ?? this.head,
    revisions: revisions ?? this.revisions,
    lastKnownRevision: lastKnownRevision ?? this.lastKnownRevision,
    busy: busy ?? this.busy,
    message: clearMessage ? null : (message ?? this.message),
    messageIsError: messageIsError ?? this.messageIsError,
    conflictingServerRevision: clearConflict
        ? null
        : (conflictingServerRevision ?? this.conflictingServerRevision),
    recoveryCodeMissing: recoveryCodeMissing ?? this.recoveryCodeMissing,
    lastFullBackupAt: lastFullBackupAt ?? this.lastFullBackupAt,
  );
}

/// Drives the cloud backup surface.
///
/// Rebuilds when the account or the entitlement changes, so signing out or a
/// lapsed subscription closes the feature without anything having to listen.
@Riverpod(keepAlive: true)
class CloudBackupNotifier extends _$CloudBackupNotifier {
  CloudBackupService? _service;
  String? _deviceId;
  int _maxSizeBytes = 0;

  /// Durable state for this device.
  ///
  /// Resolved on each use rather than assigned in [build]: a method reached
  /// before the first build finished -- which a test override or a fast tap
  /// both produce -- would otherwise hit an uninitialised field.
  CloudBackupStore get _store =>
      CloudBackupStore(storage: ref.read(secureStorageServiceProvider));

  /// The backup scope is a device preference rather than account state, so it
  /// has its own store and survives signing out.
  BackupScopeStore get _scopeStore =>
      BackupScopeStore(storage: ref.read(secureStorageServiceProvider));

  @override
  Future<CloudBackupState> build() async {
    ref.watch(secureStorageServiceProvider);

    final account = await ref.watch(accountProvider.future);
    if (!account.isSignedIn) {
      return const CloudBackupState(blocker: CloudBackupBlocker.signedOut);
    }

    final entitlement = await ref.watch(entitlementProvider.future);
    if (!entitlement.hasCloudBackup) {
      return const CloudBackupState(blocker: CloudBackupBlocker.notEntitled);
    }

    _deviceId = account.session!.deviceId;
    _maxSizeBytes = entitlement.entitlement.limits.maxBackupSizeBytes;

    _service = CloudBackupService(
      api: CloudBackupApi(
        client: ref.watch(accountProvider.notifier).apiClient,
      ),
      sync: ref.watch(e2eeCloudSyncServiceProvider),
      readPendingUploadId: _store.readPendingUploadId,
      writePendingUploadId: _store.writePendingUploadId,
      newUploadId: const Uuid().v4,
    );

    final configured = await _store.isConfigured();
    final lastKnownRevision = await _store.readLastKnownRevision();
    final lastFullBackupAt = await _store.readLastFullBackupAt();
    final recoveryCodeMissing =
        configured && await _store.readRecoveryCode() == null;

    if (configured) {
      return CloudBackupState(
        lastKnownRevision: lastKnownRevision,
        recoveryCodeMissing: recoveryCodeMissing,
        lastFullBackupAt: lastFullBackupAt,
      );
    }

    // This device has no passphrase. Whether that means "set one up" or "you
    // already have one, type it" is the server's answer, not this device's:
    // deciding it locally is what let a second device invent a new passphrase
    // and upload an empty vault over the first device's backup.
    VaultHead? head;
    try {
      head = await _service!.head();
    } on Object {
      // Offline. Stay on setup rather than guessing, and say nothing
      // misleading: the head is re-read the next time this builds.
      return CloudBackupState(
        blocker: CloudBackupBlocker.notConfigured,
        lastFullBackupAt: lastFullBackupAt,
      );
    }

    return CloudBackupState(
      blocker: head.isEmpty
          ? CloudBackupBlocker.notConfigured
          : CloudBackupBlocker.needsExistingPassphrase,
      head: head,
      lastFullBackupAt: lastFullBackupAt,
    );
  }

  /// Adopts a passphrase that already protects this account's backup.
  ///
  /// Verifies it against the newest stored revision before keeping it, and
  /// uploads nothing: a device joining an account has nothing worth sending
  /// yet, and sending anyway is exactly how the first device's backup was
  /// overwritten.
  Future<bool> unlockExisting({
    required String secret,
    BackupUnlockMethod method = BackupUnlockMethod.passphrase,
    String? recoveryCode,
  }) async {
    final service = _service;
    if (service == null) return false;

    final current = state.value ?? const CloudBackupState();
    state = AsyncValue.data(current.copyWith(busy: true, clearMessage: true));

    try {
      final head = await service.head();

      if (head.isEmpty) {
        state = AsyncValue.data(
          current.copyWith(
            busy: false,
            blocker: CloudBackupBlocker.notConfigured,
            message: 'This account has no backup to unlock yet.',
            messageIsError: true,
          ),
        );

        return false;
      }

      final opened = await service.canOpen(
        revision: head.currentRevision,
        secret: secret,
        unlockWith: method,
      );

      if (opened == null) {
        state = AsyncValue.data(
          current.copyWith(
            busy: false,
            message: method == BackupUnlockMethod.recoveryCode
                ? 'That recovery code does not open this backup.'
                : 'That passphrase does not open this backup.',
            messageIsError: true,
          ),
        );

        return false;
      }

      // Only a passphrase can be stored as the passphrase. Unlocking with a
      // recovery code proves ownership but is not the secret future uploads
      // are sealed with, so that path stops here and asks for the passphrase.
      if (method == BackupUnlockMethod.recoveryCode) {
        state = AsyncValue.data(
          current.copyWith(
            busy: false,
            message:
                'Recovery code accepted. Set a passphrase for this device to '
                'finish, or restore from the app that still has one.',
            messageIsError: false,
          ),
        );

        return true;
      }

      await _store.writePassphrase(secret);
      if (recoveryCode != null && recoveryCode.isNotEmpty) {
        await _store.writeRecoveryCode(recoveryCode);
      }

      // The vault's sync key, if this backup carries one. It cannot be derived
      // or invented: every device has to hold the same key, and the only place
      // it exists is inside an envelope. A v3 backup has none, and this device
      // learns it from the first v4 backup it opens instead.
      await _store.adoptSyncKey(opened.syncKey);

      state = AsyncValue.data(
        CloudBackupState(
          head: head,
          recoveryCodeMissing: recoveryCode == null || recoveryCode.isEmpty,
          message:
              'Unlocked. Restore revision ${head.currentRevision} to bring '
              'this device up to date before backing up from here.',
        ),
      );

      return true;
    } on Object catch (e) {
      state = AsyncValue.data(
        current.copyWith(
          busy: false,
          message: 'Could not reach the backup: $e',
          messageIsError: true,
        ),
      );

      return false;
    }
  }

  /// Stores the sync passphrase and takes the first backup.
  ///
  /// The recovery code is passed through to the envelope and never persisted:
  /// it exists only in what the user wrote down.
  Future<void> configure({
    required String passphrase,
    required String recoveryCode,
  }) async {
    final service = _service;
    if (service == null) return;

    // Belt and braces against the bug this flow used to have: even if the UI
    // somehow offered first-time setup on a device joining an account that
    // already has a backup, refuse rather than upload over it.
    try {
      final head = await service.head();

      if (!head.isEmpty) {
        _publish(
          (s) => s.copyWith(
            blocker: CloudBackupBlocker.needsExistingPassphrase,
            head: head,
            message:
                'This account already has a backup. Unlock it with the '
                'passphrase you set on your other device instead of creating '
                'a new one.',
            messageIsError: true,
          ),
        );

        return;
      }
    } on Object {
      // Offline: fall through. The upload below will fail on its own and say
      // so, which is better than blocking setup on a network hiccup.
    }

    await _store.writePassphrase(passphrase);
    await _store.writeRecoveryCode(recoveryCode);

    final current = state.value ?? const CloudBackupState();
    state = AsyncValue.data(
      current.copyWith(clearBlocker: true, recoveryCodeMissing: false),
    );

    await backUpNow();
  }

  /// Reads what the server holds.
  Future<void> refresh() async {
    final service = _service;
    if (service == null) return;

    await _run((state) async {
      final head = await service.head();

      return state.copyWith(
        head: head,
        message: null,
        clearMessage: true,
        clearConflict: true,
      );
    });
  }

  /// Loads revision metadata for the restore list.
  Future<void> loadRevisions() async {
    final service = _service;
    if (service == null) return;

    await _run(
      (state) async => state.copyWith(revisions: await service.revisions()),
    );
  }

  /// Seals the database and uploads it.
  ///
  /// [force] overwrites a newer backup from another device and is only ever
  /// passed from an explicit user choice.
  Future<void> backUpNow({bool force = false}) async {
    final service = _service;
    final deviceId = _deviceId;
    if (service == null || deviceId == null) return;

    final passphrase = await _store.readPassphrase();
    if (passphrase == null) {
      _publish(
        (s) => s.copyWith(
          blocker: CloudBackupBlocker.notConfigured,
          message: 'Set a sync passphrase first.',
          messageIsError: true,
        ),
      );

      return;
    }

    // Every upload carries the recovery code this device knows, not just the
    // first one. Sealing it into the setup backup alone made the recovery path
    // cover exactly one revision and then quietly stop.
    final recoveryCode = await _store.readRecoveryCode();
    final scope = await _scopeStore.read(BackupTarget.cloud);

    // Automatic sync needs a key that outlives the passphrase, and a backup is
    // the only place it can live. The first device to switch sync on mints it;
    // every other device learns it by opening a backup that carries it, which
    // is why sync cannot start before one exists.
    final syncKey = await _store.syncKeyForUpload(
      autoSyncEnabled: await _scopeStore.readAutoSyncEnabled(),
    );

    // Where this snapshot sits in the operation log. A device that restores it
    // resumes pulling from here instead of replaying a log that reaches back
    // further than the server still keeps -- and without it that device counts
    // from zero, re-applying everything it just restored.
    final syncClock = await ref
        .read(appDatabaseProvider)
        .syncJournal
        ?.readState();

    // App settings live in secure storage, not the database, so they are read
    // here and handed over rather than reached for inside the sync service.
    final settings = scope.contains(BackupCategory.settings)
        ? (await ref.read(settingsRepositoryProvider).loadSettings()).toJson()
        : null;

    await _run((state) async {
      final result = await service.upload(
        db: ref.read(appDatabaseProvider),
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: _maxSizeBytes,
        recoveryCode: recoveryCode,
        force: force,
        scope: scope,
        settings: settings,
        syncKey: syncKey,
        syncClock: syncClock?.lastSeenClock,
      );

      if (!result.succeeded) {
        return state.copyWith(
          message: result.message,
          messageIsError: true,
          conflictingServerRevision: result.serverRevision,
        );
      }

      await _store.writeLastKnownRevision(result.revision!);

      // Only a complete backup resets the clock the partial-history warning
      // is measured against.
      DateTime? lastFullBackupAt;
      if (scope.isFull) {
        lastFullBackupAt = DateTime.now();
        await _store.writeLastFullBackupAt(lastFullBackupAt);
      }

      return state.copyWith(
        lastKnownRevision: result.revision,
        head: await service.head(),
        lastFullBackupAt: lastFullBackupAt,
        message: scope.isFull
            ? 'Backed up as revision ${result.revision}.'
            : 'Backed up as revision ${result.revision} '
                  '(${scope.toManifest().length} of '
                  '${BackupScope.full.toManifest().length} categories).',
        messageIsError: false,
        clearConflict: true,
      );
    });
  }

  /// Downloads [revision] and restores it over the local database.
  Future<void> restore({
    required int revision,
    required String secret,
    BackupUnlockMethod unlockWith = BackupUnlockMethod.passphrase,
  }) async {
    final service = _service;
    if (service == null) return;

    await _run((state) async {
      final result = await service.restore(
        db: ref.read(appDatabaseProvider),
        revision: revision,
        secret: secret,
        unlockWith: unlockWith,
      );

      await _store.writeLastKnownRevision(revision);
      await _store.adoptSyncKey(result.syncKey);

      // Settings come back as the blob they were stored as. Applying them is
      // this notifier's job, not the sync service's: the service owns the
      // database and knows nothing about secure storage.
      final restoredSettings = result.settings;
      final settingsNotes = restoredSettings == null
          ? const <String>[]
          : await ref
                .read(settingsProvider.notifier)
                .applyRestoredSettings(restoredSettings);

      // The restore wrote straight to the database, so every list notifier is
      // still holding what it read at startup. Without this the app shows the
      // old data until it is restarted -- which is what "reopen the app to see
      // everything" used to paper over.
      invalidateRestoredData(ref);

      // Repairs are reported, never swallowed. A host restored without its
      // credentials still looks restored on the list, and finding that out at
      // connection time reads as "the backup broke my keys".
      final notes = [
        result.warning,
        ...result.repairs.messages,
        ...settingsNotes,
      ].nonNulls.toList();

      return state.copyWith(
        lastKnownRevision: revision,
        message: notes.isEmpty
            ? 'Restored revision $revision.'
            : 'Restored revision $revision. ${notes.join(' ')}',
        messageIsError: result.warning != null,
        clearConflict: true,
      );
    });
  }

  /// Deletes the vault and every revision on the server.
  Future<void> deleteVault() async {
    final service = _service;
    if (service == null) return;

    await _run((state) async {
      await service.deleteVault();

      return state.copyWith(
        head: VaultHead.empty,
        revisions: const [],
        message: 'The cloud backup and every revision were deleted.',
        messageIsError: false,
        clearConflict: true,
      );
    });
  }

  /// Forgets the passphrase and settings on this device, leaving the server
  /// copy alone.
  Future<void> forgetOnThisDevice() async {
    await _store.clear();
    ref.invalidateSelf();
  }

  /// Teaches this device the recovery code so its backups carry one.
  ///
  /// Verified against the newest revision first: storing an unverified code
  /// would seal future backups with a secret the user does not actually have.
  Future<bool> adoptRecoveryCode(String recoveryCode) async {
    final service = _service;
    if (service == null) return false;

    try {
      final head = await service.head();

      if (!head.isEmpty) {
        final opened = await service.canOpen(
          revision: head.currentRevision,
          secret: recoveryCode,
          unlockWith: BackupUnlockMethod.recoveryCode,
        );

        if (opened == null) {
          _publish(
            (s) => s.copyWith(
              message: 'That recovery code does not open this backup.',
              messageIsError: true,
            ),
          );

          return false;
        }
      }

      await _store.writeRecoveryCode(recoveryCode);
      _publish(
        (s) => s.copyWith(
          recoveryCodeMissing: false,
          message:
              'Saved. Backups from this device carry the recovery code '
              'from now on.',
          messageIsError: false,
        ),
      );

      return true;
    } on Object catch (e) {
      _publish((s) => s.copyWith(message: '$e', messageIsError: true));

      return false;
    }
  }

  /// Dismisses the last message.
  void clearMessage() =>
      _publish((s) => s.copyWith(clearMessage: true, messageIsError: false));

  /// Runs [action] with the busy flag set, turning any failure into a message
  /// rather than an exception: nothing on this surface is worth crashing a
  /// settings screen over.
  Future<void> _run(
    Future<CloudBackupState> Function(CloudBackupState state) action,
  ) async {
    final current = state.value ?? const CloudBackupState();
    state = AsyncValue.data(current.copyWith(busy: true, clearMessage: true));

    try {
      state = AsyncValue.data((await action(current)).copyWith(busy: false));
    } on ApiException catch (e) {
      state = AsyncValue.data(
        current.copyWith(
          busy: false,
          message: e.statusCode == 403
              ? 'Your plan does not include cloud backup.'
              : 'The server refused the request (${e.code}).',
          messageIsError: true,
        ),
      );
    } on ApiTransportException {
      state = AsyncValue.data(
        current.copyWith(
          busy: false,
          message: 'The server could not be reached.',
          messageIsError: true,
        ),
      );
    } on BackupEnvelopeException catch (e) {
      state = AsyncValue.data(
        current.copyWith(busy: false, message: e.reason, messageIsError: true),
      );
    } on Object catch (e) {
      if (kDebugMode) debugPrint('Cloud backup action failed: $e');
      state = AsyncValue.data(
        current.copyWith(busy: false, message: '$e', messageIsError: true),
      );
    }
  }

  void _publish(CloudBackupState Function(CloudBackupState state) update) {
    final current = state.value;
    if (current == null) return;

    state = AsyncValue.data(update(current));
  }
}
