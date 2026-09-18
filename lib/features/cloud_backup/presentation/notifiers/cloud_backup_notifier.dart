import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../core/sync/e2ee_cloud_sync_service.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../account/presentation/notifiers/account_notifier.dart';
import '../../../billing/presentation/notifiers/entitlement_notifier.dart';
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

  /// Entitled, but no sync passphrase has been set up here yet.
  notConfigured,
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

  /// True when a backup runs when the app closes.
  final bool backupOnExit;

  /// True while an upload, restore or delete is running.
  final bool busy;

  /// One sentence about the last action, success or failure.
  final String? message;

  /// True when [message] describes a failure.
  final bool messageIsError;

  /// Set when the last upload lost a race, so the UI can offer to overwrite.
  final int? conflictingServerRevision;

  const CloudBackupState({
    this.blocker,
    this.head,
    this.revisions = const [],
    this.lastKnownRevision,
    this.backupOnExit = false,
    this.busy = false,
    this.message,
    this.messageIsError = false,
    this.conflictingServerRevision,
  });

  bool get isReady => blocker == null;

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
    bool? backupOnExit,
    bool? busy,
    String? message,
    bool? messageIsError,
    int? conflictingServerRevision,
    bool clearBlocker = false,
    bool clearMessage = false,
    bool clearConflict = false,
  }) => CloudBackupState(
    blocker: clearBlocker ? null : (blocker ?? this.blocker),
    head: head ?? this.head,
    revisions: revisions ?? this.revisions,
    lastKnownRevision: lastKnownRevision ?? this.lastKnownRevision,
    backupOnExit: backupOnExit ?? this.backupOnExit,
    busy: busy ?? this.busy,
    message: clearMessage ? null : (message ?? this.message),
    messageIsError: messageIsError ?? this.messageIsError,
    conflictingServerRevision: clearConflict
        ? null
        : (conflictingServerRevision ?? this.conflictingServerRevision),
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

    return CloudBackupState(
      blocker: configured ? null : CloudBackupBlocker.notConfigured,
      lastKnownRevision: await _store.readLastKnownRevision(),
      backupOnExit: await _store.readBackupOnExit(),
    );
  }

  /// Stores the sync passphrase and takes the first backup.
  ///
  /// The recovery code is passed through to the envelope and never persisted:
  /// it exists only in what the user wrote down.
  Future<void> configure({
    required String passphrase,
    required String recoveryCode,
  }) async {
    await _store.writePassphrase(passphrase);

    final current = state.value ?? const CloudBackupState();
    state = AsyncValue.data(current.copyWith(clearBlocker: true));

    await backUpNow(recoveryCode: recoveryCode);
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
      (state) async =>
          state.copyWith(revisions: await service.revisions()),
    );
  }

  /// Seals the database and uploads it.
  ///
  /// [force] overwrites a newer backup from another device and is only ever
  /// passed from an explicit user choice.
  Future<void> backUpNow({String? recoveryCode, bool force = false}) async {
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

    await _run((state) async {
      final result = await service.upload(
        db: ref.read(appDatabaseProvider),
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: _maxSizeBytes,
        recoveryCode: recoveryCode,
        force: force,
      );

      if (!result.succeeded) {
        return state.copyWith(
          message: result.message,
          messageIsError: true,
          conflictingServerRevision: result.serverRevision,
        );
      }

      await _store.writeLastKnownRevision(result.revision!);

      return state.copyWith(
        lastKnownRevision: result.revision,
        head: await service.head(),
        message: 'Backed up as revision ${result.revision}.',
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

      return state.copyWith(
        lastKnownRevision: revision,
        message:
            result.warning ??
            'Restored revision $revision. Reopen the app to see everything.',
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

  /// Turns the backup-on-close behaviour on or off.
  Future<void> setBackupOnExit(bool enabled) async {
    await _store.writeBackupOnExit(enabled);
    _publish((s) => s.copyWith(backupOnExit: enabled));
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
    state = AsyncValue.data(
      current.copyWith(busy: true, clearMessage: true),
    );

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
        current.copyWith(
          busy: false,
          message: e.reason,
          messageIsError: true,
        ),
      );
    } on Object catch (e) {
      if (kDebugMode) debugPrint('Cloud backup action failed: $e');
      state = AsyncValue.data(
        current.copyWith(
          busy: false,
          message: '$e',
          messageIsError: true,
        ),
      );
    }
  }

  void _publish(CloudBackupState Function(CloudBackupState state) update) {
    final current = state.value;
    if (current == null) return;

    state = AsyncValue.data(update(current));
  }
}
