import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../core/crypto/encryption_engine.dart';
import '../../../core/sync/backup_envelope.dart';
import '../../../shared/storage/secure_storage_service.dart';
import '../../vault/data/vault_key_service.dart';

/// How often a backup runs without being asked.
///
/// Off by default. A feature shipping is not a reason to start writing to
/// someone's account on a schedule they did not choose.
enum BackupFrequency {
  off('off', null),
  hourly('hourly', Duration(hours: 1)),
  daily('daily', Duration(days: 1)),
  weekly('weekly', Duration(days: 7));

  const BackupFrequency(this.wireName, this.interval);

  /// Stable name in storage. Never derived from [name]: renaming a Dart
  /// identifier must not silently change someone's schedule.
  final String wireName;

  /// How long between backups, or null when off.
  final Duration? interval;

  /// What the user is actually promised.
  ///
  /// There is no background task, so the check runs when the app is open or
  /// coming back to the foreground. "Daily" therefore means "once a day, the
  /// first time you open it" -- and saying so is better than a schedule that
  /// quietly does not happen on a device nobody opened.
  String get promise => switch (this) {
    BackupFrequency.off => 'Only when you ask.',
    BackupFrequency.hourly => 'At most once an hour, while the app is open.',
    BackupFrequency.daily => 'Once a day, the first time you open the app.',
    BackupFrequency.weekly => 'Once a week, the first time you open the app.',
  };

  String get label => switch (this) {
    BackupFrequency.off => 'Off',
    BackupFrequency.hourly => 'Hourly',
    BackupFrequency.daily => 'Daily',
    BackupFrequency.weekly => 'Weekly',
  };

  static BackupFrequency fromWireName(String? value) {
    for (final frequency in BackupFrequency.values) {
      if (frequency.wireName == value) return frequency;
    }

    return BackupFrequency.off;
  }
}

/// Durable state for cloud backup on this device.
///
/// The passphrase, the recovery code and the sync key are kept in the
/// keychain, sealed under the vault key. Each of them opens every envelope or
/// operation this account writes, and those carry the vault key and the
/// identity secrets -- so stored in the clear they would be the vault key in
/// all but name. With a master password set that was a way around it: the
/// vault key is kept wrapped precisely so that reading the keychain is not
/// enough, and these three handed a keychain reader everything anyway.
/// Sealed, they are exactly as readable as the vault key itself: with no
/// master password, as before; with one, only while the vault is unlocked.
///
/// Not storing them at all would mean prompting on every upload, which is how
/// automatic backup stops happening.
///
/// The recovery code is kept here too. Not storing it was the original
/// intention, and it was wrong: the code is sealed into each envelope at
/// upload time, so a device that has forgotten it writes backups the code
/// cannot open. The recovery path would then silently cover only the very
/// first backup ever taken, which is worse than useless -- it is a promise
/// that quietly stops being true.
final class CloudBackupStore {
  final SecureStorageService storage;

  /// The vault key the secrets are sealed under. Throws
  /// [VaultLockedException] while a master password keeps the vault locked,
  /// and so does every read or write of a secret.
  final Future<SecretKey> Function() vaultKey;

  final EncryptionEngine _crypto;

  CloudBackupStore({
    required this.storage,
    required this.vaultKey,
    EncryptionEngine? crypto,
  }) : _crypto = crypto ?? EncryptionEngine();

  /// The sync passphrase, or null when cloud backup has not been set up.
  Future<String?> readPassphrase() => _readSecret(_passphraseKey);

  Future<void> writePassphrase(String passphrase) =>
      _writeSecret(_passphraseKey, passphrase);

  /// The recovery code, when this device knows it.
  ///
  /// Null on a device that adopted an existing passphrase without being given
  /// the code. Backups written there carry no recovery path, and the UI says
  /// so rather than letting the user believe otherwise.
  Future<String?> readRecoveryCode() => _readSecret(_recoveryCodeKey);

  Future<void> writeRecoveryCode(String recoveryCode) =>
      _writeSecret(_recoveryCodeKey, recoveryCode);

  /// Whether this device knows the recovery code. Answers behind a locked
  /// vault: it looks for the code, it does not open it.
  Future<bool> hasRecoveryCode() => _hasSecret(_recoveryCodeKey);

  /// Whether cloud backup has been configured on this device. Answers behind
  /// a locked vault, for the same reason.
  Future<bool> isConfigured() => _hasSecret(_passphraseKey);

  /// The idempotency key of an upload that was started and never confirmed.
  ///
  /// Read before every upload so a retry after a dropped reply is recognised
  /// by the server as the same write instead of storing a second revision.
  Future<String?> readPendingUploadId() async {
    final value = await storage.read(key: _pendingUploadKey);

    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> writePendingUploadId(String? uploadId) => uploadId == null
      ? storage.delete(key: _pendingUploadKey)
      : storage.write(key: _pendingUploadKey, value: uploadId);

  /// The same, for the sync vault.
  ///
  /// A separate key, and it has to be: the idempotency key is what the server
  /// answers a retry with. Shared between the two vaults, a retried backup
  /// upload could be answered with the sync vault's stored revision -- a
  /// success for a write that never happened.
  Future<String?> readPendingSyncUploadId() async {
    final value = await storage.read(key: _pendingSyncUploadKey);

    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> writePendingSyncUploadId(String? uploadId) => uploadId == null
      ? storage.delete(key: _pendingSyncUploadKey)
      : storage.write(key: _pendingSyncUploadKey, value: uploadId);

  /// The revision number this device last uploaded or restored, for showing
  /// "you are up to date" without a round trip.
  Future<int?> readLastKnownRevision() async {
    final value = await storage.read(key: _lastRevisionKey);

    return value == null ? null : int.tryParse(value);
  }

  Future<void> writeLastKnownRevision(int revision) =>
      storage.write(key: _lastRevisionKey, value: '$revision');

  /// The vault's sync key, once this device has learned it.
  ///
  /// Base64. The design note kept this in memory only, recovered by opening
  /// the newest envelope at every start. In practice that means a network
  /// round trip and an Argon2id derivation before sync can do anything, on
  /// every launch, for a key the passphrase beside it already unlocks. Stored
  /// sealed under the vault key, like the passphrase.
  Future<String?> readSyncKey() => _readSecret(_syncKeyKey);

  Future<void> writeSyncKey(String base64Key) =>
      _writeSecret(_syncKeyKey, base64Key);

  /// Keeps the vault's sync key, when a backup handed one over.
  ///
  /// Never overwrites one this device already holds. A backup is a snapshot of
  /// some moment, possibly an old one, and letting any revision that happens
  /// to be restored redefine the account's key would be a worse rule than
  /// keeping the one already in hand. The account's *ground* is the one thing
  /// allowed to overrule it -- see [adoptGroundSyncKey].
  Future<void> adoptSyncKey(SecretKey? syncKey) async {
    if (syncKey == null) return;
    if (await readSyncKey() != null) return;

    await writeSyncKey(base64.encode(await syncKey.extractBytes()));
  }

  /// Takes the key from the account's sync ground, overruling this device's.
  ///
  /// The ground is what every joining device starts from, so the key it
  /// carries is the account's by definition. A device holding a different one
  /// minted its own before any ground existed -- two devices switching sync on
  /// at the same time is all it takes -- and from then on each pushes a log
  /// the other silently discards. Nothing fails, nothing is empty, and neither
  /// screen says a word.
  ///
  /// Returns true when the stored key actually changed, which is the caller's
  /// signal that everything this device sent under the old key has to be
  /// written again.
  Future<bool> adoptGroundSyncKey(SecretKey? syncKey) async {
    if (syncKey == null) return false;

    final incoming = base64.encode(await syncKey.extractBytes());
    if (await readSyncKey() == incoming) return false;

    await writeSyncKey(incoming);

    return true;
  }

  /// The key the next upload should seal in, minting one if it is time.
  ///
  /// Returns null while automatic sync is off, which keeps the envelope at v3
  /// and readable by builds that predate v4. There is no reason to spend that
  /// compatibility on a feature the user has not asked for.
  ///
  /// The first device to switch sync on mints the key; every other device
  /// learns it by opening a backup that carries it. That is why sync cannot
  /// start before a backup exists -- the key has nowhere else to live.
  Future<Uint8List?> syncKeyForUpload({
    required bool autoSyncEnabled,
    Uint8List Function()? mint,
  }) async {
    final stored = await readSyncKey();
    if (stored != null) return base64.decode(stored);

    if (!autoSyncEnabled) return null;

    final minted = (mint ?? BackupEnvelope().generateSyncKey)();
    await writeSyncKey(base64.encode(minted));

    return minted;
  }

  /// The sync ground this device last wrote or started from.
  ///
  /// Two numbers: which revision it was, and the clock it recorded. The clock
  /// lives inside the ciphertext, so asking the server for it means
  /// downloading and decrypting a snapshot -- too much to spend on a question
  /// asked at every start.
  ///
  /// Null when this device has never touched a ground, which is also what a
  /// device that has not joined reports.
  Future<({int revision, int clock})?> readGroundMark() async {
    final value = await storage.read(key: _groundMarkKey);
    if (value == null || value.isEmpty) return null;

    final parts = value.split(':');
    if (parts.length != 2) return null;

    final revision = int.tryParse(parts[0]);
    final clock = int.tryParse(parts[1]);
    if (revision == null || clock == null) return null;

    return (revision: revision, clock: clock);
  }

  Future<void> writeGroundMark({required int revision, required int clock}) =>
      storage.write(key: _groundMarkKey, value: '$revision:$clock');

  /// How often a backup runs on its own.
  Future<BackupFrequency> readBackupFrequency() async =>
      BackupFrequency.fromWireName(await storage.read(key: _frequencyKey));

  Future<void> writeBackupFrequency(BackupFrequency frequency) =>
      storage.write(key: _frequencyKey, value: frequency.wireName);

  /// When a scheduled backup last ran, and the clock the database stood at.
  ///
  /// The clock is what answers "has anything changed". Every local write and
  /// every applied remote operation moves it, and it keeps moving whether or
  /// not automatic sync is on -- unlike the outbox, which sync drains, and
  /// which would therefore read as "nothing changed" on exactly the devices
  /// that change the most.
  Future<({DateTime at, int clock})?> readAutoBackupMark() async {
    final value = await storage.read(key: _autoBackupMarkKey);
    if (value == null || value.isEmpty) return null;

    final separator = value.lastIndexOf(':');
    if (separator < 0) return null;

    final at = DateTime.tryParse(value.substring(0, separator));
    final clock = int.tryParse(value.substring(separator + 1));
    if (at == null || clock == null) return null;

    return (at: at, clock: clock);
  }

  Future<void> writeAutoBackupMark({
    required DateTime at,
    required int clock,
  }) => storage.write(
    key: _autoBackupMarkKey,
    value: '${at.toIso8601String()}:$clock',
  );

  /// When this device last wrote a backup that held everything.
  ///
  /// A vault whose whole history is partial only reveals that at restore
  /// time, which is the worst moment to learn it. This is what the warning on
  /// the Cloud Backup screen is measured against.
  Future<DateTime?> readLastFullBackupAt() async {
    final value = await storage.read(key: _lastFullBackupKey);

    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> writeLastFullBackupAt(DateTime at) =>
      storage.write(key: _lastFullBackupKey, value: at.toIso8601String());

  /// Forgets everything about cloud backup on this device.
  ///
  /// Used when the vault is deleted from the server and when the account is
  /// signed out: a passphrase left behind would be offered against the next
  /// account's vault, which it cannot open.
  Future<void> clear() async {
    for (final key in const [_passphraseKey, _recoveryCodeKey, _syncKeyKey]) {
      await storage.delete(key: key);
      await storage.delete(key: _sealed(key));
    }
    await storage.delete(key: _pendingUploadKey);
    await storage.delete(key: _pendingSyncUploadKey);
    await storage.delete(key: _lastRevisionKey);
    await storage.delete(key: _backupOnExitKey);
    await storage.delete(key: _lastFullBackupKey);
    await storage.delete(key: _groundMarkKey);
    await storage.delete(key: _autoBackupMarkKey);
    // The schedule goes too. Left behind, a device whose vault was deleted
    // still believes it backs up hourly, and the first passphrase set on it
    // afterwards silently starts a schedule nobody asked for.
    await storage.delete(key: _frequencyKey);
  }

  /// A secret, opened with the vault key.
  ///
  /// A value written by an earlier build sits in the clear under the old
  /// key. It is returned as it is -- refusing it would stop backup on every
  /// device that has one -- and moved under the vault key on the way, unless
  /// the vault is locked, in which case the next read moves it.
  Future<String?> _readSecret(String key) async {
    final sealed = await storage.read(key: _sealed(key));
    if (sealed != null && sealed.isNotEmpty) {
      return _crypto.decrypt(
        encryptedBase64: sealed,
        secretKey: await vaultKey(),
      );
    }

    final legacy = await storage.read(key: key);
    if (legacy == null || legacy.isEmpty) return null;

    try {
      await _writeSecret(key, legacy);
    } on VaultLockedException {
      // Moved on the next read with the vault open.
    }

    return legacy;
  }

  Future<void> _writeSecret(String key, String value) async {
    final sealed = await _crypto.encrypt(
      plaintext: value,
      secretKey: await vaultKey(),
    );
    await storage.write(key: _sealed(key), value: sealed);
    await storage.delete(key: key);
  }

  Future<bool> _hasSecret(String key) async {
    for (final k in [_sealed(key), key]) {
      final value = await storage.read(key: k);
      if (value != null && value.isNotEmpty) return true;
    }

    return false;
  }

  /// Where the sealed copy of [key] lives. A key of its own rather than a
  /// marker inside the value: a passphrase can be any string, including one
  /// that looks like a marker.
  static String _sealed(String key) => '${key}_sealed';

  static const String _passphraseKey = 'shellvibe_sync_passphrase';
  static const String _recoveryCodeKey = 'shellvibe_sync_recovery_code';
  static const String _pendingUploadKey = 'shellvibe_sync_pending_upload';
  static const String _pendingSyncUploadKey =
      'shellvibe_sync_pending_ground_upload';
  static const String _lastRevisionKey = 'shellvibe_sync_last_revision';

  /// Read by nothing. Kept only so [clear] removes what earlier builds wrote:
  /// the "back up when the app closes" switch was never wired to the app
  /// lifecycle, and a scheduled backup replaces it.
  static const String _backupOnExitKey = 'shellvibe_sync_backup_on_exit';
  static const String _lastFullBackupKey = 'shellvibe_sync_last_full_backup';
  static const String _groundMarkKey = 'shellvibe_sync_ground_mark';
  static const String _frequencyKey = 'shellvibe_backup_frequency';
  static const String _autoBackupMarkKey = 'shellvibe_backup_auto_mark';
  static const String _syncKeyKey = 'shellvibe_sync_key';
}
