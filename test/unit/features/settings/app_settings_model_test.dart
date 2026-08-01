import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/features/settings/domain/models/app_settings_model.dart';

void main() {
  group('AppSettingsModel Unit Tests', () {
    test('Default values are set correctly', () {
      const settings = AppSettingsModel();
      expect(settings.themeMode, equals(ThemeMode.dark));
      expect(settings.palette, equals(AppPalette.dark));
      expect(settings.terminalPalette, equals(TerminalPalette.dark));
      expect(settings.fontFamily, equals('RobotoMono'));
      expect(settings.fontSize, equals(14.0));
      expect(settings.cursorStyle, equals(AppCursorStyle.block));
      expect(settings.autoLockTimerSeconds, equals(0));
      expect(settings.clipboardAutoClearSeconds, equals(30));
    });

    test('copyWith produces updated model', () {
      const settings = AppSettingsModel();
      final updated = settings.copyWith(
        palette: AppPalette.catppuccin,
        terminalPalette: TerminalPalette.dracula,
        fontSize: 16.0,
        autoLockTimerSeconds: 60,
      );

      expect(updated.palette, equals(AppPalette.catppuccin));
      expect(updated.terminalPalette, equals(TerminalPalette.dracula));
      expect(updated.fontSize, equals(16.0));
      expect(updated.autoLockTimerSeconds, equals(60));
      expect(updated.fontFamily, equals('RobotoMono'));
    });

    test('toJson and fromJson serialization cycle', () {
      const settings = AppSettingsModel(
        themeMode: ThemeMode.light,
        palette: AppPalette.nord,
        terminalPalette: TerminalPalette.solarizedDark,
        fontFamily: 'FiraCode',
        fontSize: 18.0,
        cursorStyle: AppCursorStyle.underline,
        autoLockTimerSeconds: 300,
        clipboardAutoClearSeconds: 15,
      );

      final json = settings.toJson();
      final restored = AppSettingsModel.fromJson(json);

      expect(restored.themeMode, equals(ThemeMode.light));
      expect(restored.palette, equals(AppPalette.nord));
      expect(restored.terminalPalette, equals(TerminalPalette.solarizedDark));
      expect(restored.fontFamily, equals('FiraCode'));
      expect(restored.fontSize, equals(18.0));
      expect(restored.cursorStyle, equals(AppCursorStyle.underline));
      expect(restored.autoLockTimerSeconds, equals(300));
      expect(restored.clipboardAutoClearSeconds, equals(15));
    });
  });
}
