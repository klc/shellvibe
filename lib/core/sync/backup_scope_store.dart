import '../../shared/storage/secure_storage_service.dart';
import 'backup_scope.dart';

/// Which selection a scope belongs to.
///
/// Three separate answers, deliberately. They were one preference at first,
/// on the reasoning that "what my backups contain" should not mean two things
/// -- but they are not one question. A file saved to disk, a backup uploaded
/// to the vault and a background sync that runs on its own are three different
/// acts with three different risks, and a user who narrows one has not said
/// anything about the others.
enum BackupTarget {
  /// The encrypted `.svb` file written to disk.
  file('shellvibe_backup_scope_file'),

  /// A manual backup uploaded to the cloud vault.
  cloud('shellvibe_backup_scope_cloud'),

  /// What automatic sync carries, in both directions.
  autoSync('shellvibe_sync_scope');

  const BackupTarget(this.storageKey);

  final String storageKey;
}

/// What this device puts in a backup, per target.
///
/// A device preference, not account state: it outlives signing out, which is
/// why it does not live in `CloudBackupStore`.
final class BackupScopeStore {
  final SecureStorageService storage;

  const BackupScopeStore({required this.storage});

  /// The chosen scope, or everything when nothing has been chosen.
  ///
  /// Defaulting to everything is the only safe default: a backup that quietly
  /// holds less than the user assumes is discovered at restore time.
  Future<BackupScope> read(BackupTarget target) async {
    final value = await storage.read(key: target.storageKey);
    if (value != null && value.isNotEmpty) {
      return BackupScope.fromManifest(value.split(','));
    }

    // The single shared preference these three replaced. Read once so a user
    // who had already narrowed their backups does not silently get everything
    // again on the next upgrade.
    final legacy = await storage.read(key: _legacyKey);
    if (legacy != null && legacy.isNotEmpty) {
      return BackupScope.fromManifest(legacy.split(','));
    }

    return BackupScope.full;
  }

  Future<void> write(BackupTarget target, BackupScope scope) => storage.write(
    key: target.storageKey,
    value: scope.toManifest().join(','),
  );

  /// Whether automatic sync runs on this device.
  ///
  /// Off until the user turns it on. Background sync writes to the account on
  /// its own schedule, and that is not something to start doing because a
  /// feature shipped.
  Future<bool> readAutoSyncEnabled() async =>
      await storage.read(key: _autoSyncEnabledKey) == 'true';

  Future<void> writeAutoSyncEnabled(bool enabled) =>
      storage.write(key: _autoSyncEnabledKey, value: '$enabled');

  static const String _legacyKey = 'shellvibe_backup_scope';
  static const String _autoSyncEnabledKey = 'shellvibe_sync_enabled';
}
