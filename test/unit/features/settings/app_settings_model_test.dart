import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/models/mosh_prediction_mode.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_palette.dart';

void main() {
  group('AppSettingsModel Unit Tests', () {
    test('Default values are set correctly', () {
      const settings = AppSettingsModel();
      expect(settings.themeMode, equals(ThemeMode.dark));
      expect(settings.palette, equals(AppPalette.oled));
      expect(settings.terminalPalette, equals(TerminalPalette.oled));
      expect(settings.fontFamily, equals('RobotoMono'));
      expect(settings.uiFontFamily, equals('InterTight'));
      expect(settings.fontSize, equals(14.0));
      expect(settings.lineHeightFactor, equals(1.4));
      expect(settings.cursorStyle, equals(AppCursorStyle.block));
      expect(settings.enableLigatures, isTrue);
      expect(settings.drawBoldTextWithBrightColors, isTrue);
      expect(settings.moshPrediction, equals(MoshPredictionMode.adaptive));
      expect(settings.autoLockTimerSeconds, equals(0));
      expect(settings.clipboardAutoClearSeconds, equals(30));
      expect(settings.activeWorkspaceId, equals('default'));
      expect(settings.keepRunningInTray, isTrue);
    });

    test('keepRunningInTray round-trips and defaults on when absent', () {
      final off = const AppSettingsModel().copyWith(keepRunningInTray: false);
      expect(
        AppSettingsModel.fromJson(off.toJson()).keepRunningInTray,
        isFalse,
      );
      // Settings saved before the option existed keep the app in the tray.
      final legacy = off.toJson()..remove('keepRunningInTray');
      expect(AppSettingsModel.fromJson(legacy).keepRunningInTray, isTrue);
    });

    test('copyWith produces updated model', () {
      const settings = AppSettingsModel();
      final updated = settings.copyWith(
        palette: AppPalette.catppuccin,
        terminalPalette: TerminalPalette.dracula,
        enableLigatures: false,
        drawBoldTextWithBrightColors: false,
        fontSize: 16.0,
        lineHeightFactor: 1.7,
        autoLockTimerSeconds: 60,
        moshPrediction: MoshPredictionMode.always,
        activeWorkspaceId: 'client-ops',
      );

      expect(updated.palette, equals(AppPalette.catppuccin));
      expect(updated.terminalPalette, equals(TerminalPalette.dracula));
      expect(updated.enableLigatures, isFalse);
      expect(updated.drawBoldTextWithBrightColors, isFalse);
      expect(updated.fontSize, equals(16.0));
      expect(updated.lineHeightFactor, equals(1.7));
      expect(updated.autoLockTimerSeconds, equals(60));
      expect(updated.moshPrediction, equals(MoshPredictionMode.always));
      expect(updated.fontFamily, equals('RobotoMono'));
      expect(updated.activeWorkspaceId, equals('client-ops'));
    });

    test('toJson and fromJson serialization cycle', () {
      const settings = AppSettingsModel(
        themeMode: ThemeMode.light,
        palette: AppPalette.nord,
        terminalPalette: TerminalPalette.solarizedDark,
        fontFamily: 'FiraCode',
        uiFontFamily: 'IBMPlexSans',
        fontSize: 18.0,
        lineHeightFactor: 1.6,
        cursorStyle: AppCursorStyle.underline,
        drawBoldTextWithBrightColors: false,
        moshPrediction: MoshPredictionMode.never,
        autoLockTimerSeconds: 300,
        clipboardAutoClearSeconds: 15,
        activeWorkspaceId: 'client-ops',
      );

      final json = settings.toJson();
      final restored = AppSettingsModel.fromJson(json);

      expect(restored.themeMode, equals(ThemeMode.light));
      expect(restored.palette, equals(AppPalette.nord));
      expect(restored.terminalPalette, equals(TerminalPalette.solarizedDark));
      expect(restored.fontFamily, equals('FiraCode'));
      expect(restored.uiFontFamily, equals('IBMPlexSans'));
      expect(restored.fontSize, equals(18.0));
      expect(restored.lineHeightFactor, equals(1.6));
      expect(restored.cursorStyle, equals(AppCursorStyle.underline));
      expect(restored.drawBoldTextWithBrightColors, isFalse);
      expect(restored.moshPrediction, equals(MoshPredictionMode.never));
      expect(restored.autoLockTimerSeconds, equals(300));
      expect(restored.clipboardAutoClearSeconds, equals(15));
      expect(restored.activeWorkspaceId, equals('client-ops'));
    });

    test('older settings JSON defaults active workspace to default', () {
      final restored = AppSettingsModel.fromJson(const {
        'themeMode': 'dark',
        'palette': 'dark',
      });

      expect(restored.activeWorkspaceId, equals('default'));
      expect(restored.lineHeightFactor, equals(1.4));
      expect(restored.drawBoldTextWithBrightColors, isTrue);
      expect(restored.moshPrediction, equals(MoshPredictionMode.adaptive));
    });

    test(
      'serializes and deserializes all new palettes and fonts correctly',
      () {
        for (final palette in AppPalette.values) {
          for (final termPalette in TerminalPalette.values) {
            final settings = AppSettingsModel(
              palette: palette,
              terminalPalette: termPalette,
              fontFamily: 'JetBrainsMono',
            );

            final restored = AppSettingsModel.fromJson(settings.toJson());
            expect(restored.palette, equals(palette));
            expect(restored.terminalPalette, equals(termPalette));
            expect(restored.fontFamily, equals('JetBrainsMono'));
          }
        }
      },
    );
  });
}
