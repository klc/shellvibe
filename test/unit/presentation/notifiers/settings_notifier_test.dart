import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terly2/features/settings/domain/models/app_settings_model.dart';
import 'package:terly2/features/settings/presentation/notifiers/settings_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsNotifier State Transition Unit Tests', () {
    late ProviderContainer container;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('Loads default settings on initial build', () async {
      final settings = await container.read(settingsProvider.future);
      expect(settings.themeMode, equals(ThemeMode.dark));
      expect(settings.palette, equals(AppPalette.dark));
      expect(settings.fontSize, equals(14.0));
      expect(settings.fontFamily, equals('RobotoMono'));
    });

    test('setThemeMode updates theme mode in state', () async {
      await container.read(settingsProvider.future);
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setThemeMode(ThemeMode.light);
      var current = container.read(settingsProvider).value!;
      expect(current.themeMode, equals(ThemeMode.light));

      await notifier.setThemeMode(ThemeMode.dark);
      current = container.read(settingsProvider).value!;
      expect(current.themeMode, equals(ThemeMode.dark));
    });

    test('setPalette updates color palette in state', () async {
      await container.read(settingsProvider.future);
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setPalette(AppPalette.catppuccin);
      var current = container.read(settingsProvider).value!;
      expect(current.palette, equals(AppPalette.catppuccin));

      await notifier.setPalette(AppPalette.nord);
      current = container.read(settingsProvider).value!;
      expect(current.palette, equals(AppPalette.nord));

      await notifier.setPalette(AppPalette.oled);
      current = container.read(settingsProvider).value!;
      expect(current.palette, equals(AppPalette.oled));
    });

    test('setFontSize and setFontFamily update font configurations', () async {
      await container.read(settingsProvider.future);
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setFontSize(16.0);
      await notifier.setFontFamily('Fira Code');

      final current = container.read(settingsProvider).value!;
      expect(current.fontSize, equals(16.0));
      expect(current.fontFamily, equals('Fira Code'));
    });

    test('setCursorStyle and autoLockTimer updates', () async {
      await container.read(settingsProvider.future);
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setCursorStyle(AppCursorStyle.underline);
      await notifier.setAutoLockTimer(600);

      final current = container.read(settingsProvider).value!;
      expect(current.cursorStyle, equals(AppCursorStyle.underline));
      expect(current.autoLockTimerSeconds, equals(600));
    });
  });
}
