import 'dart:convert';
import '../../../../shared/storage/secure_storage_service.dart';
import '../../domain/models/app_settings_model.dart';

class SettingsRepository {
  static const String _settingsKey = 'terly2_app_settings';
  final SecureStorageService _storage;

  SettingsRepository(this._storage);

  Future<AppSettingsModel> loadSettings() async {
    try {
      final jsonStr = await _storage.read(key: _settingsKey);
      if (jsonStr == null || jsonStr.isEmpty) {
        return const AppSettingsModel();
      }
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
