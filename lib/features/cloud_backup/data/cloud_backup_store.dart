import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../core/sync/backup_envelope.dart';
import '../../../shared/storage/secure_storage_service.dart';

/// Durable state for cloud backup on this device.
///
/// The sync passphrase is kept in the same hardware-backed keychain the vault
/// DEK already lives in. That is a deliberate trade: an attacker who can read
/// this keychain can already read the vault key and therefore the secrets
/// themselves, so storing the passphrase beside it gives up nothing new -- and
/// not storing it would mean prompting on every upload, which is how automatic
/// backup stops happening.
///
/// The recovery code is kept here too. Not storing it was the original
/// intention, and it was wrong: the code is sealed into each envelope at
/// upload time, so a device that has forgotten it writes backups the code
/// cannot open. The recovery path would then silently cover only the very
/// first backup ever taken, which is worse than useless -- it is a promise
/// that quietly stops being true.
final class CloudBackupStore {
  final SecureStorageService storage;

  const CloudBackupStore({required this.storage});

  /// The sync passphrase, or null when cloud backup has not been set up.
  Future<String?> readPassphrase() async {
    final value = await storage.read(key: _passphraseKey);

    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> writePassphrase(String passphrase) =>
      storage.write(key: _passphraseKey, value: passphrase);

  /// The recovery code, when this device knows it.
  ///
  /// Null on a device that adopted an existing passphrase without being given
  /// the code. Backups written there carry no recovery path, and the UI says
  /// so rather than letting the user believe otherwise.
  Future<String?> readRecoveryCode() async {
    final value = await storage.read(key: _recoveryCodeKey);

    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> writeRecoveryCode(String recoveryCode) =>
      storage.write(key: _recoveryCodeKey, value: recoveryCode);

  /// Whether cloud backup has been configured on this device.
  Future<bool> isConfigured() async => await readPassphrase() != null;

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
  /// every launch, for a key the passphrase beside it already unlocks. The
  /// trade is the same one the passphrase itself made: an attacker who can
  /// read this keychain can already read the vault key and therefore the
  /// secrets, so storing the sync key here gives up nothing new.
  Future<String?> readSyncKey() async {
    final value = await storage.read(key: _syncKeyKey);

    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> writeSyncKey(String base64Key) =>
      storage.write(key: _syncKeyKey, value: base64Key);

  /// Keeps the vault's sync key, when a backup handed one over.
  ///
  /// Never overwrites one this device already holds. Two devices that each
  /// minted a key would seal their own into their own backups, and every
  /// operation either of them wrote would be unreadable to the other -- with
  /// nothing failing, because both would simply skip what they could not open.
  Future<void> adoptSyncKey(SecretKey? syncKey) async {
    if (syncKey == null) return;
    if (await readSyncKey() != null) return;

    await writeSyncKey(base64.encode(await syncKey.extractBytes()));
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
    await storage.delete(key: _passphraseKey);
    await storage.delete(key: _recoveryCodeKey);
    await storage.delete(key: _pendingUploadKey);
    await storage.delete(key: _pendingSyncUploadKey);
    await storage.delete(key: _lastRevisionKey);
    await storage.delete(key: _backupOnExitKey);
    await storage.delete(key: _lastFullBackupKey);
    await storage.delete(key: _syncKeyKey);
  }

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
  static const String _syncKeyKey = 'shellvibe_sync_key';
}
