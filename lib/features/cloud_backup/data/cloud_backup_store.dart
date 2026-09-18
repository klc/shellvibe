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
/// The recovery code is never stored, here or anywhere else.
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

  Future<void> writePendingUploadId(String? uploadId) =>
      uploadId == null
      ? storage.delete(key: _pendingUploadKey)
      : storage.write(key: _pendingUploadKey, value: uploadId);

  /// The revision number this device last uploaded or restored, for showing
  /// "you are up to date" without a round trip.
  Future<int?> readLastKnownRevision() async {
    final value = await storage.read(key: _lastRevisionKey);

    return value == null ? null : int.tryParse(value);
  }

  Future<void> writeLastKnownRevision(int revision) =>
      storage.write(key: _lastRevisionKey, value: '$revision');

  /// Whether the user asked for a backup when the app closes.
  Future<bool> readBackupOnExit() async =>
      await storage.read(key: _backupOnExitKey) == 'true';

  Future<void> writeBackupOnExit(bool enabled) =>
      storage.write(key: _backupOnExitKey, value: '$enabled');

  /// Forgets everything about cloud backup on this device.
  ///
  /// Used when the vault is deleted from the server and when the account is
  /// signed out: a passphrase left behind would be offered against the next
  /// account's vault, which it cannot open.
  Future<void> clear() async {
    await storage.delete(key: _passphraseKey);
    await storage.delete(key: _pendingUploadKey);
    await storage.delete(key: _lastRevisionKey);
    await storage.delete(key: _backupOnExitKey);
  }

  static const String _passphraseKey = 'shellvibe_sync_passphrase';
  static const String _pendingUploadKey = 'shellvibe_sync_pending_upload';
  static const String _lastRevisionKey = 'shellvibe_sync_last_revision';
  static const String _backupOnExitKey = 'shellvibe_sync_backup_on_exit';
}
