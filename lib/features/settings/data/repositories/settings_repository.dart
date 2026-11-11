import 'dart:convert';
import '../../../../shared/storage/secure_storage_service.dart';
import '../../domain/models/app_settings_model.dart';

class SettingsRepository {
  /// Renamed from `terly2_app_settings` for 1.0. [SecureStorageService.read]
  /// migrates a `shellvibe_`-prefixed key from its `terly2_` predecessor on the
  /// first read, so an install that predates the rename keeps its settings
  /// instead of silently reverting to defaults.
  static const String _settingsKey = 'shellvibe_app_settings';
  final SecureStorageService _storage;

  SettingsRepository(this._storage);

  /// The stored settings, or the defaults when none are stored.
  ///
  /// A failed read throws rather than returning the defaults: a denied
  /// keychain prompt or a Linux keyring that is not unlocked yet does not mean
  /// there are no settings, and treating it that way lets the next edit
  /// overwrite them all with defaults. A blob that cannot be parsed is another
  /// matter; nothing in it can be recovered, so it reads as no settings.
  Future<AppSettingsModel> loadSettings() async {
    final jsonStr = await _storage.read(key: _settingsKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      return const AppSettingsModel();
    }
    try {
      final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      return AppSettingsModel.fromJson(jsonMap);
    } catch (_) {
      return const AppSettingsModel();
    }
  }

  Future<void> saveSettings(AppSettingsModel settings) async {
    final jsonStr = jsonEncode(settings.toJson());
    await _storage.write(key: _settingsKey, value: jsonStr);
  }
}
