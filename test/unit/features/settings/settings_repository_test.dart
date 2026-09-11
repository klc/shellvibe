import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/settings/data/repositories/settings_repository.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

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
      expect(settings.palette, equals(AppPalette.oled));
    });

    // The storage key moved from `terly2_app_settings` to
    // `shellvibe_app_settings` for 1.0. SecureStorageService migrates a
    // `shellvibe_`-prefixed key from its `terly2_` predecessor on first read;
    // if that ever stops working, every install that predates the rename
    // silently reverts to defaults, which is the kind of failure a user reads
    // as "the app forgot everything" rather than as a bug worth reporting.
    test('settings written under the pre-1.0 key survive the rename', () async {
      const legacy =
          '{"themeMode":"light","palette":"nord","fontSize":19.0,'
          '"autoLockTimerSeconds":120}';
      FlutterSecureStorage.setMockInitialValues({
        'terly2_app_settings': legacy,
      });
      storage = SecureStorageService();
      repository = SettingsRepository(storage);

      final loaded = await repository.loadSettings();
      expect(loaded.themeMode, equals(ThemeMode.light));
      expect(loaded.palette, equals(AppPalette.nord));
      expect(loaded.fontSize, equals(19.0));
      expect(loaded.autoLockTimerSeconds, equals(120));

      // Migrated, not merely read through: the value is now under the new key,
      // so the legacy read happens once rather than on every launch.
      expect(await storage.read(key: 'shellvibe_app_settings'), equals(legacy));
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
