import '../../shared/storage/secure_storage_service.dart';
import 'backup_scope.dart';

/// What this device puts in a backup.
///
/// A device preference, not account state: it applies to the encrypted file
/// saved to disk as much as to the cloud vault, and it outlives signing out.
/// That is why it does not live in `CloudBackupStore`, which is cleared when
/// the account goes away.
final class BackupScopeStore {
  final SecureStorageService storage;

  const BackupScopeStore({required this.storage});

  /// The chosen scope, or everything when nothing has been chosen.
  ///
  /// Defaulting to everything is the only safe default: a backup that quietly
  /// holds less than the user assumes is discovered at restore time.
  Future<BackupScope> read() async {
    final value = await storage.read(key: _key);
    if (value == null || value.isEmpty) return BackupScope.full;

    return BackupScope.fromManifest(value.split(','));
  }

  Future<void> write(BackupScope scope) =>
      storage.write(key: _key, value: scope.toManifest().join(','));

  static const String _key = 'shellvibe_backup_scope';
}
