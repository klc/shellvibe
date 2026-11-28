import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/restored_data.dart';
import '../../../../core/api/api_exception.dart';
import '../../../../core/sync/account_key.dart';
import '../../../../core/sync/backup_scope_store.dart';
import '../../../../core/sync/e2ee_cloud_sync_service.dart';
import '../../../../core/sync/sync_journal.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../account/presentation/notifiers/account_notifier.dart';
import '../../../billing/presentation/notifiers/entitlement_notifier.dart';
import '../../../settings/presentation/notifiers/settings_notifier.dart';
import '../../../vault/data/vault_key_service.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../../vault/presentation/notifiers/vault_notifier.dart';
import '../../data/account_key_api.dart';
import '../../data/cloud_backup_api.dart';
import '../../data/cloud_backup_store.dart';
import '../../domain/account_key_service.dart';
import '../../domain/backup_frequency.dart';
import '../../domain/cloud_backup_service.dart';
import 'sync_notifier.dart';

part 'cloud_backup_notifier.g.dart';

/// Said on a device whose account key the account no longer has.
const String kAccountKeyMismatchMessage =
    'This account\'s encryption was reset or set up again on another device, '
    'so the key on this one no longer opens it. Remove cloud backup from this '
    'device and add it again. Nothing on this device is lost.';

/// Why the cloud backup surface is not usable right now.
enum CloudBackupBlocker {
  /// No account on this device. The only thing standing between a user and
  /// cloud backup -- it is on the free plan, so there is nothing to buy.
  signedOut,

  /// Signed in, the account has no backup yet, and this device has no
  /// passphrase: a genuine first-time setup.
  notConfigured,

  /// Signed in, this device has no passphrase, but the account already has a
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

  /// How often a backup runs without being asked.
  final BackupFrequency frequency;

  /// When a scheduled backup last ran on this device.
  final DateTime? lastAutoBackupAt;

  /// True when this device holds the account key, and so can hand it to
  /// another device and restore without being asked for a secret.
  final bool usesAccountKey;

  /// True when the account has a key and this device does not hold it yet:
  /// another device can hand it over, as well as the passphrase opening it.
  final bool accountHasKey;

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
    this.frequency = BackupFrequency.off,
    this.lastAutoBackupAt,
    this.usesAccountKey = false,
    this.accountHasKey = false,
  });

  bool get isReady => blocker == null;

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
    BackupFrequency? frequency,
    DateTime? lastAutoBackupAt,
    bool? usesAccountKey,
    bool? accountHasKey,
    bool clearBlocker = false,
    bool clearMessage = false,
    bool clearConflict = false,
    bool clearLastAutoBackupAt = false,
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
    frequency: frequency ?? this.frequency,
    lastAutoBackupAt: clearLastAutoBackupAt
        ? null
        : (lastAutoBackupAt ?? this.lastAutoBackupAt),
    usesAccountKey: usesAccountKey ?? this.usesAccountKey,
    accountHasKey: accountHasKey ?? this.accountHasKey,
  );
}

/// Drives the cloud backup surface.
///
/// Rebuilds when the account or the plan's limits change, so signing out
/// closes the feature without anything having to listen.
@Riverpod(keepAlive: true)
class CloudBackupNotifier extends _$CloudBackupNotifier {
  CloudBackupService? _service;
  AccountKeyService? _accountKeys;
  String? _deviceId;
  int _maxSizeBytes = 0;
  Timer? _schedule;

  /// How often the schedule is re-examined while the app is open.
  ///
  /// Not the backup interval: this is how often "is one due" gets asked. An
  /// hourly backup on a machine left open for a day has to happen without
  /// someone closing and reopening the app.
  static const Duration scheduleTick = Duration(minutes: 15);

  /// Durable state for this device.
  ///
  /// Resolved on each use rather than assigned in [build]: a method reached
  /// before the first build finished -- which a test override or a fast tap
  /// both produce -- would otherwise hit an uninitialised field.
  CloudBackupStore get _store => CloudBackupStore(
    storage: ref.read(secureStorageServiceProvider),
    vaultKey: ref.read(vaultKeyServiceProvider).getDek,
  );

  /// The backup scope is a device preference rather than account state, so it
  /// has its own store and survives signing out.
  BackupScopeStore get _scopeStore =>
      BackupScopeStore(storage: ref.read(secureStorageServiceProvider));

  @override
  Future<CloudBackupState> build() async {
    ref.onDispose(() {
      _schedule?.cancel();
      // A rebuild keeps this instance and hands it a new `ref`, so
      // `ref.mounted` cannot tell a run started by the build before from one
      // of this build's. The service can: a run that finds a different one
      // -- or none, while this build is still working out the account --
      // belongs to a build that is gone.
      _service = null;
      _accountKeys = null;
    });
    ref.watch(secureStorageServiceProvider);

    final account = await ref.watch(accountProvider.future);
    if (!account.isSignedIn) {
      return const CloudBackupState(blocker: CloudBackupBlocker.signedOut);
    }

    // The passphrase, the recovery code and the revision this device last
    // knew belong to the account they were set up under. Kept under another,
    // the schedule seals backups that account's devices cannot open and
    // uploads them over its vault. Forgotten, setup starts over against the
    // vault this account actually has.
    final owner = await _store.readBackupAccount();
    final userId = account.session!.userId;
    if (owner != userId) {
      // No record means a build before this one, on the account it set up.
      if (owner != null) await _store.clear();
      await _store.writeBackupAccount(userId);
    }

    // Read for its limits, not for permission: cloud backup is free, and
    // the upload size the server will accept is the one thing here the
    // client cannot know on its own. Only the limit: the entitlement
    // republishes a few times right after sign-in, and each one would
    // otherwise be a rebuild that schedules another backup run.
    _deviceId = account.session!.deviceId;
    _maxSizeBytes = await ref.watch(
      entitlementProvider.selectAsync(
        (s) => s.entitlement.limits.maxBackupSizeBytes,
      ),
    );

    final client = ref.watch(accountProvider.notifier).apiClient;

    _service = CloudBackupService(
      api: CloudBackupApi(client: client),
      sync: ref.watch(e2eeCloudSyncServiceProvider),
      readPendingUploadId: _store.readPendingUploadId,
      writePendingUploadId: _store.writePendingUploadId,
      newUploadId: const Uuid().v4,
    );
    _accountKeys = AccountKeyService(
      store: _store,
      api: AccountKeyApi(client: client),
      deviceId: _deviceId!,
      records: AccountKeyRecord(crypto: ref.watch(encryptionEngineProvider)),
    );

    final configured = await _store.isConfigured();
    final lastKnownRevision = await _store.readLastKnownRevision();
    final lastFullBackupAt = await _store.readLastFullBackupAt();
    final frequency = await _store.readBackupFrequency();
    final autoMark = await _store.readAutoBackupMark();

    _startSchedule(frequency);
    final usesAccountKey = configured && await _store.hasAccountKey();

    // A device that seals with the passphrase has to know the recovery code
    // itself to seal it in. One that holds the account key does not: the
    // account's record carries the recovery slot, and whether it has one is
    // read off the server once this build has returned.
    final recoveryCodeMissing =
        configured && !usesAccountKey && !await _store.hasRecoveryCode();

    if (configured) {
      // A device that has been closed longer than the interval is due the
      // moment it opens. There is no background task, so this is the only
      // moment a scheduled backup can happen at all.
      //
      // On the event queue, not here: the schedule reads the frequency from
      // `state`, which is still loading until this method returns. Called
      // inline it read "off" and returned, so a cold start never backed up
      // and the first chance was the timer, a quarter of an hour later.
      //
      // The account key first, so a device that can move to it does so
      // before it seals anything: the backup that follows is then one every
      // other device holding the key opens without a passphrase.
      Future(() async {
        await _settleAccountKey();
        unawaited(maybeBackUpOnSchedule());
      });

      // The passphrase is sealed under the vault key, so behind a master
      // password the step above could read nothing and gave up. Without this
      // a device whose vault is locked at launch -- every launch, for a user
      // with a master password -- would never move to the account key.
      ref.listen(vaultProvider, (previous, next) {
        final unlocked = next.value?.status == VaultStatus.unlocked;
        final wasUnlocked = previous?.value?.status == VaultStatus.unlocked;
        if (unlocked && !wasUnlocked) unawaited(_settleAccountKey());
      });

      return CloudBackupState(
        lastKnownRevision: lastKnownRevision,
        recoveryCodeMissing: recoveryCodeMissing,
        lastFullBackupAt: lastFullBackupAt,
        frequency: frequency,
        lastAutoBackupAt: autoMark?.at,
        usesAccountKey: usesAccountKey,
      );
    }

    // This device has no passphrase. Whether that means "set one up" or "you
    // already have one, type it" is the server's answer, not this device's:
    // deciding it locally is what let a second device invent a new passphrase
    // and upload an empty vault over the first device's backup.
    //
    // The key record answers first: it belongs to the account rather than to
    // either vault, so deleting the cloud backup does not make an account
    // that is still syncing look like a new one. An account without a record
    // is asked the old way, and there the sync vault counts as well as the
    // backup one, for the same reason.
    final VaultHead head;
    final bool accountHasKey;
    try {
      accountHasKey = (await _accountKeys!.head()).exists;
      head = accountHasKey
          ? await _service!.head()
          : (await _existingVault()).head;
    } on Object {
      // Offline. Stay on setup rather than guessing, and say nothing
      // misleading: the head is re-read the next time this builds.
      return CloudBackupState(
        blocker: CloudBackupBlocker.notConfigured,
        lastFullBackupAt: lastFullBackupAt,
        frequency: frequency,
        lastAutoBackupAt: autoMark?.at,
      );
    }

    return CloudBackupState(
      blocker: head.isEmpty && !accountHasKey
          ? CloudBackupBlocker.notConfigured
          : CloudBackupBlocker.needsExistingPassphrase,
      head: head,
      lastFullBackupAt: lastFullBackupAt,
      frequency: frequency,
      lastAutoBackupAt: autoMark?.at,
      accountHasKey: accountHasKey,
    );
  }

  /// The vault a device joining an account without a key record proves its
  /// passphrase against: the backup, or the sync ground when the backup is
  /// empty.
  ///
  /// "Delete cloud backup" removes the backup vault and leaves the account
  /// syncing. Looking at the backup alone, a device joining after that was
  /// offered first-time setup, chose a new passphrase, and could then open
  /// nothing the account held.
  Future<({CloudBackupService service, VaultHead head})>
  _existingVault() async {
    final backup = _service!;
    final head = await backup.head();
    if (!head.isEmpty) return (service: backup, head: head);

    final ground = CloudBackupService(
      api: CloudBackupApi(
        client: ref.read(accountProvider.notifier).apiClient,
        kind: VaultKind.sync,
      ),
      sync: ref.read(e2eeCloudSyncServiceProvider),
      readPendingUploadId: _store.readPendingSyncUploadId,
      writePendingUploadId: _store.writePendingSyncUploadId,
      newUploadId: const Uuid().v4,
    );
    final groundHead = await ground.head();

    return groundHead.isEmpty
        ? (service: backup, head: head)
        : (service: ground, head: groundHead);
  }

  /// Moves this device to the account key when it can, and drops the
  /// passphrase once nothing needs it.
  ///
  /// Runs on every start and after every backup, and each step is safe to
  /// repeat: a device closed halfway through picks up at the same question.
  /// Every failure here is a reason to try again later, never a state to
  /// report -- the device keeps working exactly as it did before.
  Future<void> _settleAccountKey() async {
    final keys = _accountKeys;
    if (keys == null) return;

    try {
      if (await _store.hasAccountKey()) {
        // The account may have been reset, or set up again, from somewhere
        // else. Said now rather than at the next backup, which fails anyway.
        try {
          await keys.current();
        } on BackupEnvelopeException {
          if (!ref.mounted || !identical(keys, _accountKeys)) return;
          _publish(
            (s) => s.copyWith(
              message: kAccountKeyMismatchMessage,
              messageIsError: true,
            ),
          );

          return;
        }
      } else {
        final outcome = await keys.migrate();
        if (!ref.mounted || !identical(keys, _accountKeys)) return;

        if (outcome == AccountKeyOutcome.wrongSecret) {
          _publish(
            (s) => s.copyWith(
              message:
                  'The passphrase on this device does not match the '
                  'account. Forget it here and enter the one your other '
                  'devices use.',
              messageIsError: true,
            ),
          );
        }
        if (outcome != AccountKeyOutcome.ready) return;

        // Sync read the passphrase when it was built. It seals with the key
        // from here on, and rewrites the ground so a device joining by code
        // can start from it.
        ref.invalidate(syncProvider);
        _publish((s) => s.copyWith(usesAccountKey: true));
      }

      final hasRecoveryCode = await keys.hasRecoveryCode();
      if (!ref.mounted || !identical(keys, _accountKeys)) return;
      _publish((s) => s.copyWith(recoveryCodeMissing: !hasRecoveryCode));

      if (await _store.hasPassphrase() && await _groundOpensWithAccountKey()) {
        // The key has been checked against the account's record -- `current`
        // throws otherwise -- and the one thing this device reads on its own,
        // the sync ground, opens with it.
        if (await keys.current() != null) await _store.forgetPassphrase();
      }
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[Backup] account key not settled: $e');
    }
  }

  /// Whether the account's sync ground is one the account key opens, or
  /// there is none.
  ///
  /// The passphrase stays on this device until it is: a device that falls
  /// behind starts over from the ground, and one sealed with the passphrase
  /// would then be a ground it could no longer read.
  Future<bool> _groundOpensWithAccountKey() async {
    final revisions = await CloudBackupApi(
      client: ref.read(accountProvider.notifier).apiClient,
      kind: VaultKind.sync,
    ).revisions();

    return revisions.isEmpty ||
        BackupEnvelope.opensWithAccountKey(revisions.first.schemaVersion);
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
      if ((await _accountKeys!.head()).exists) {
        return await _unlockAccountKey(current, secret, method);
      }

      final (service: vault, :head) = await _existingVault();

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

      final opened = await vault.canOpen(
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

      // Sync read "no passphrase" when it was built and watches nothing that
      // changes here, so without this it stays stopped until the next launch.
      ref.invalidate(syncProvider);

      state = AsyncValue.data(
        current.copyWith(
          busy: false,
          clearBlocker: true,
          head: head,
          recoveryCodeMissing: recoveryCode == null || recoveryCode.isEmpty,
          message: _unlockedMessage(await service.head()),
          messageIsError: false,
          clearConflict: true,
        ),
      );

      // Not awaited: the unlock is done. This is the device moving on to the
      // account key, if the account can have one yet.
      unawaited(_settleAccountKey());

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

  /// Unlocks an account that has a key: [secret] opens the account's record,
  /// and this device keeps the key it finds there, not the secret.
  Future<bool> _unlockAccountKey(
    CloudBackupState current,
    String secret,
    BackupUnlockMethod method,
  ) async {
    final outcome = await _accountKeys!.unlock(secret: secret, method: method);

    if (outcome != AccountKeyOutcome.ready) {
      state = AsyncValue.data(
        current.copyWith(
          busy: false,
          message: method == BackupUnlockMethod.recoveryCode
              ? 'That recovery code does not open this account.'
              : 'That passphrase does not open this account.',
          messageIsError: true,
        ),
      );

      return false;
    }

    await _joined(current);

    return true;
  }

  /// Takes the account key another device handed over.
  ///
  /// Returns a sentence for the user when it could not be kept, null when
  /// this device is now set up.
  Future<String?> adoptAccountKey(Uint8List accountKey) async {
    final keys = _accountKeys;
    if (keys == null) return 'Sign in to finish setting up this device.';

    final outcome = await keys.adopt(accountKey);
    if (outcome != AccountKeyOutcome.ready) {
      return 'The other device sent a key that does not belong to this '
          'account. Nothing was changed.';
    }

    await _joined(state.value ?? const CloudBackupState());

    return null;
  }

  /// The account key, for handing to another device.
  ///
  /// Throws `VaultLockedException` behind a locked vault, which is the point:
  /// a device somebody else picked up cannot add a device of theirs.
  Future<Uint8List?> accountKeyForHandoff() async =>
      (await _accountKeys?.current())?.bytes;

  /// What every way of joining an account with a key ends with.
  Future<void> _joined(CloudBackupState current) async {
    final head = await _service!.head();
    final hasRecoveryCode = await _accountKeys!.hasRecoveryCode();

    // Sync read "no key" when it was built and watches nothing that changes
    // here, so without this it stays stopped until the next launch.
    ref.invalidate(syncProvider);

    state = AsyncValue.data(
      current.copyWith(
        busy: false,
        clearBlocker: true,
        head: head,
        usesAccountKey: true,
        accountHasKey: false,
        recoveryCodeMissing: !hasRecoveryCode,
        message: _unlockedMessage(head),
        messageIsError: false,
        clearConflict: true,
      ),
    );
  }

  static String _unlockedMessage(VaultHead head) => head.isEmpty
      ? 'Unlocked.'
      : 'Unlocked. Restore revision ${head.currentRevision} to bring this '
            'device up to date before backing up from here.';

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
    final AccountKeyOutcome outcome;
    try {
      final head = (await _existingVault()).head;

      // The account key is created here when the server allows it, and the
      // server is also where a second device setting up at the same moment
      // is found out: one write wins, and the other is told there is a key.
      outcome = head.isEmpty
          ? await _accountKeys!.create(
              passphrase: passphrase,
              recoveryCode: recoveryCode,
            )
          : AccountKeyOutcome.alreadyExists;

      if (outcome == AccountKeyOutcome.alreadyExists) {
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
      // Not knowing is not the same as the vault being empty. Storing the
      // passphrase here marks the device configured, and the next scheduled
      // backup would then seal this device's data under a passphrase no other
      // device has and upload it over the account's backup -- the bug the
      // check above exists to stop, reached through a dropped connection.
      _publish(
        (s) => s.copyWith(
          message:
              'Could not reach the server to check for an existing backup. '
              'Nothing was saved; try again once you are online.',
          messageIsError: true,
        ),
      );

      return;
    }

    // With a key, neither secret is kept: the key is what this device seals
    // with, and the two secrets are what open it somewhere else.
    final usesAccountKey = outcome == AccountKeyOutcome.ready;
    if (!usesAccountKey) {
      await _store.writePassphrase(passphrase);
      await _store.writeRecoveryCode(recoveryCode);
    }

    final current = state.value ?? const CloudBackupState();
    state = AsyncValue.data(
      current.copyWith(
        clearBlocker: true,
        recoveryCodeMissing: false,
        usesAccountKey: usesAccountKey,
      ),
    );

    await backUpNow();

    // After the backup, not before: both mint the sync key when there is
    // none, and two running at once would each keep a different one.
    ref.invalidate(syncProvider);
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

    final scope = await _scopeStore.read(BackupTarget.cloud);
    final autoSyncEnabled = await _scopeStore.readAutoSyncEnabled();

    final AccountKey? accountKey;
    final String? passphrase;
    final String? recoveryCode;
    final Uint8List? syncKey;
    try {
      // Read with the record as the account has it now, so what this backup
      // carries is not a copy this device took at some earlier time.
      accountKey = await _accountKeys?.current();
      passphrase = accountKey == null ? await _store.readPassphrase() : null;

      // Every upload carries the recovery code this device knows, not just
      // the first one. Sealing it into the setup backup alone made the
      // recovery path cover exactly one revision and then quietly stop.
      recoveryCode = await _store.readRecoveryCode();

      // Automatic sync needs a key that outlives the passphrase, and a backup
      // is the only place it can live. The first device to switch sync on
      // mints it; every other device learns it by opening a backup that
      // carries it, which is why sync cannot start before one exists.
      syncKey = await _store.syncKeyForUpload(autoSyncEnabled: autoSyncEnabled);
    } on VaultLockedException {
      // The secrets are sealed under the vault key, and so is everything a
      // backup carries. Nothing to do until it is open.
      _publish(
        (s) => s.copyWith(
          message: 'Unlock the vault to back up.',
          messageIsError: true,
        ),
      );

      return;
    } on BackupEnvelopeException catch (e) {
      _publish((s) => s.copyWith(message: e.reason, messageIsError: true));

      return;
    } on ApiFailure {
      _publish(
        (s) => s.copyWith(
          message: 'The server could not be reached.',
          messageIsError: true,
        ),
      );

      return;
    }

    if (passphrase == null && accountKey == null) {
      _publish(
        (s) => s.copyWith(
          blocker: CloudBackupBlocker.notConfigured,
          message: 'Set a sync passphrase first.',
          messageIsError: true,
        ),
      );

      return;
    }

    // Where this snapshot sits in the operation log. A device that restores it
    // resumes pulling from here instead of replaying a log that reaches back
    // further than the server still keeps -- and without it that device counts
    // from zero, re-applying everything it just restored.
    final journal = ref.read(appDatabaseProvider).syncJournal;
    final syncClock = await journal?.readState();

    // The revision this upload claims to build on. Without sync, a device's
    // data is only as new as the last backup it wrote or restored, so that is
    // the base: another device's later backup then comes back as a conflict
    // for the user to settle, rather than being buried under this device's
    // older data. A device that has joined automatic sync already holds what
    // every other device wrote, so the server's current head is the truth.
    final converged =
        autoSyncEnabled && await journal?.readJoinState() == SyncJoinState.done;
    final expectedRevision = converged
        ? null
        : await _store.readLastKnownRevision() ?? 0;

    // App settings live in secure storage, not the database, so they are read
    // here and handed over rather than reached for inside the sync service.
    final settings = scope.contains(BackupCategory.settings)
        ? (await ref.read(settingsRepositoryProvider).loadSettings()).toJson()
        : null;

    await _run((state) async {
      final result = await service.upload(
        db: ref.read(appDatabaseProvider),
        passphrase: passphrase,
        accountKey: accountKey,
        deviceId: deviceId,
        maxSizeBytes: _maxSizeBytes,
        recoveryCode: recoveryCode,
        expectedRevision: expectedRevision,
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

    // A device still carrying the passphrase beside the key may be able to
    // let go of it now.
    if (accountKey != null && await _store.hasPassphrase()) {
      unawaited(_settleAccountKey());
    }
  }

  /// Downloads [revision] and restores it over the local database.
  ///
  /// [secret] is for a revision sealed with the passphrase, and for a device
  /// that holds no account key. A device with the key restores what was
  /// sealed with it without being asked anything.
  Future<void> restore({
    required int revision,
    String? secret,
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
        accountKey: await _accountKeys?.current(),
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
      invalidateRestoredData(ref.invalidate);

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
      await _store.writeLastKnownRevision(0);
      await _store.clearAutoBackupMark();

      return state.copyWith(
        clearLastAutoBackupAt: true,
        head: VaultHead.empty,
        lastKnownRevision: 0,
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
    // Sync holds what it read when it was built, and would otherwise go on
    // sealing with a key this device was just told to forget. Its place in
    // the log goes too, so adding the device again joins from scratch.
    await ref.read(syncProvider.notifier).leaveAccount();
  }

  /// Looks again after the account's encryption was reset in the web panel.
  ///
  /// This device is not set up -- that is why it was sent there -- so
  /// whatever sync state it still carries belongs to the log the reset
  /// removed.
  Future<void> checkAfterReset() async {
    await ref.read(syncProvider.notifier).leaveAccount();
    ref.invalidateSelf();
  }

  /// Gives the account [recoveryCode] as its recovery code.
  ///
  /// For a device that holds the account key, which is all this takes: the
  /// code becomes one more way to reach the key, and the passphrase is not
  /// involved. The code is new, shown once and typed back by the caller --
  /// there is nothing older to check it against.
  Future<bool> createRecoveryCode(String recoveryCode) async {
    final keys = _accountKeys;
    if (keys == null) return false;

    try {
      await keys.setRecoveryCode(recoveryCode);
      _publish(
        (s) => s.copyWith(
          recoveryCodeMissing: false,
          message: 'Saved. The recovery code opens this account from now on.',
          messageIsError: false,
        ),
      );

      return true;
    } on Object catch (e) {
      _publish(
        (s) => s.copyWith(
          message: e is BackupEnvelopeException ? e.reason : '$e',
          messageIsError: true,
        ),
      );

      return false;
    }
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

  /// Sets how often a backup runs on its own.
  Future<void> setFrequency(BackupFrequency frequency) async {
    await _store.writeBackupFrequency(frequency);
    _startSchedule(frequency);
    _publish((s) => s.copyWith(frequency: frequency));

    unawaited(maybeBackUpOnSchedule());
  }

  /// The scheduled backup already running, if one is.
  ///
  /// Static, not a field: each build schedules a run, and the run an
  /// earlier build started and the one the next schedules would otherwise
  /// seal and upload side by side.
  static Future<void>? _scheduledRun;

  /// Backs up if one is due and anything has changed.
  ///
  /// Called when the app opens, when it comes back to the foreground, on a
  /// timer while it is open, and when the frequency changes. Safe to call as
  /// often as any of those happen: everything that would make it a bad idea
  /// is checked here, and a call that lands while one is running joins it.
  /// Two overlapping runs would each seal the vault, and whichever finished
  /// second read the other's result as its own and left the mark unwritten.
  Future<void> maybeBackUpOnSchedule() async {
    // A run in flight may belong to an earlier build. Joining it would adopt
    // its result, but its `_backUpIfDue` bails out early once the service it
    // started with is gone -- so wait for it, then ask the question again.
    // Calls within one build still dedupe: the second waits for the first
    // and finds nothing due.
    final previous = _scheduledRun;
    if (previous != null) await previous.catchError((_) {});
    if (!ref.mounted) return;

    final run = _scheduledRun ??= _backUpIfDue().whenComplete(
      () => _scheduledRun = null,
    );
    return run;
  }

  Future<void> _backUpIfDue() async {
    // A restore or delete in flight owns the store; the next tick will come
    // round.
    if (state.value?.busy == true) return;

    final frequency = state.value?.frequency ?? BackupFrequency.off;
    final interval = frequency.interval;
    if (interval == null) return;

    final service = _service;
    if (service == null || _deviceId == null) return;

    // Every await below may outlive the build that started this run. A
    // disposed provider makes `ref` and `state` throw; a rebuild does not,
    // but replaces the service -- and a run carrying on past it would upload
    // under whichever account signed in meanwhile.
    bool gone() => !ref.mounted || !identical(service, _service);

    if (!await _store.isConfigured()) return;
    if (gone()) return;

    // A conflict waits for the user: restore the other device's backup or
    // overwrite it. Retrying on the next tick cannot settle it, and each try
    // seals the whole vault again only to be refused.
    if (state.value?.conflictingServerRevision != null) return;

    final mark = await _store.readAutoBackupMark();
    if (gone()) return;
    final now = DateTime.now();

    if (mark != null && now.difference(mark.at) < interval) return;

    // Has anything actually changed. Without this an hourly backup writes the
    // same bytes every hour and turns a ten revision window into ten copies
    // of one state -- which is not a history, and is exactly what someone
    // reaches for a revision list to escape.
    final clock =
        (await ref.read(appDatabaseProvider).syncJournal?.readState())
            ?.lastSeenClock ??
        0;
    if (gone()) return;

    if (mark != null && clock == mark.clock) {
      // Nothing to write, but the schedule has been honoured. Recording it
      // stops an idle device asking the same question every tick.
      await _store.writeAutoBackupMark(at: now, clock: clock);

      return;
    }

    // Sealing identity secrets needs the vault open. Skipping is right --
    // there is nothing to do behind a lock -- but silence is not: a user who
    // keeps the vault locked would see backups simply stop.
    final vault = ref.read(vaultProvider).value;
    if (vault != null && vault.status == VaultStatus.locked) {
      _publish(
        (s) => s.copyWith(
          message:
              'Scheduled backup skipped: the vault is locked. It will run '
              'once you unlock it.',
          messageIsError: false,
        ),
      );

      return;
    }

    // Never forced. A conflict means another device wrote since this one last
    // wrote or restored, and overwriting that without being asked is the one
    // move here that destroys someone's data.
    await backUpNow();
    if (gone()) return;

    // The mark is only written for an upload that actually landed. Writing it
    // after a refusal -- a conflict, a throttle, a body over the plan's limit,
    // a server that could not be reached -- would count the attempt as the
    // interval's backup and wait out the whole interval again. On a weekly
    // schedule one dropped connection is then a week with no backup, and
    // nothing says so.
    final after = state.value;
    if (after == null ||
        after.conflictingServerRevision != null ||
        after.messageIsError) {
      return;
    }

    await _store.writeAutoBackupMark(at: now, clock: clock);
    _publish((s) => s.copyWith(lastAutoBackupAt: now));
  }

  void _startSchedule(BackupFrequency frequency) {
    _schedule?.cancel();
    _schedule = null;

    if (frequency.interval == null) return;

    _schedule = Timer.periodic(
      scheduleTick,
      (_) => unawaited(maybeBackUpOnSchedule()),
    );
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
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) return;

    state = AsyncValue.data(update(current));
  }
}
