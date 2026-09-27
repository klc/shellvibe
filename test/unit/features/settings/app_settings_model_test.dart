import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/models/mosh_prediction_mode.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_palette.dart';

void main() {
  group('AppSettingsModel Unit Tests', () {
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
