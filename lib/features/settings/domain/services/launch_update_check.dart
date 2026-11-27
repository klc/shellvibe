import '../../../../shared/storage/secure_storage_service.dart';
import 'update_check_service.dart';

/// The update check the app runs on its own at launch: at most once a day,
/// silent when the feed cannot be reached, and never twice about a version
/// the user chose to skip.
///
/// The caller decides whether it runs at all: only on desktop builds outside
/// a store, and only while Settings > About leaves it on.
class LaunchUpdateCheck {
  LaunchUpdateCheck({
    required this.service,
    required this.storage,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final UpdateCheckService service;
  final SecureStorageService storage;
  final DateTime Function() _now;

  static const lastCheckedKey = 'update_check_last_checked_at';
  static const skippedVersionKey = 'update_check_skipped_version';
  static const interval = Duration(days: 1);

  /// The release to tell the user about, or null.
  Future<UpdateAvailable?> run() async {
    final now = _now().toUtc();
    final last = DateTime.tryParse(
      await storage.read(key: lastCheckedKey) ?? '',
    );
    // A clock set back counts as due rather than as checked in the future.
    if (last != null &&
        !now.isBefore(last) &&
        now.difference(last) < interval) {
      return null;
    }

    final result = await service.check();
    // Offline or rate limited: tried again at the next launch, not tomorrow.
    if (result is UpdateCheckUnavailable) return null;
    await storage.write(key: lastCheckedKey, value: now.toIso8601String());

    if (result is! UpdateAvailable) return null;
    if (result.version == await storage.read(key: skippedVersionKey)) {
      return null;
    }
    return result;
  }

  /// Stops announcing [version]; a later release is announced again.
  Future<void> skip(String version) =>
      storage.write(key: skippedVersionKey, value: version);
}
