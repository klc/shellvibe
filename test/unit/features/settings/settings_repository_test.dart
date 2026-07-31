import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/features/settings/data/repositories/settings_repository.dart';
import 'package:terly2/features/settings/domain/models/app_settings_model.dart';
import 'package:terly2/shared/storage/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureStorageService storage;
  late SettingsRepository repository;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    storage = SecureStorageService();
    repository = SettingsRepository(storage);
  });

  group('SettingsRepository Unit Tests', () {
    test('loadSettings returns default model when storage is empty', () async {
      final settings = await repository.loadSettings();
      expect(settings.themeMode, equals(ThemeMode.dark));
      expect(settings.palette, equals(AppPalette.dark));
    });

    test('saveSettings and loadSettings persists settings', () async {
      const customSettings = AppSettingsModel(
        palette: AppPalette.oled,
        fontSize: 16.0,
        autoLockTimerSeconds: 60,
      );

      await repository.saveSettings(customSettings);

      final loaded = await repository.loadSettings();
      expect(loaded.palette, equals(AppPalette.oled));
      expect(loaded.fontSize, equals(16.0));
      expect(loaded.autoLockTimerSeconds, equals(60));
    });
  });
}
