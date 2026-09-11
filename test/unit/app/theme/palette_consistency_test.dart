import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/theme/app_palette_definitions.dart';
import 'package:shellvibe/app/theme/app_theme.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';

void main() {
  group('AppPaletteDefinition & Palette Consistency Tests', () {
    for (final palette in AppPalette.values) {
      test(
        'Palette ${palette.name} defines aligned tokens and colorSchemes for dark & light',
        () {
          final def = AppPaletteDefinition.forPalette(palette);

          // Dark verification
          final darkTokens = def.darkTokens;
          final darkShad = AppPaletteDefinition.buildShadColorScheme(
            palette,
            isDark: true,
          );
          final darkTheme = AppTheme.buildTheme(
            AppSettingsModel(themeMode: ThemeMode.dark, palette: palette),
            brightness: Brightness.dark,
          );

          expect(
            darkTokens.brand,
            equals(darkTheme.colorScheme.primary),
            reason:
                'Dark palette ${palette.name} token brand must match ThemeData primary',
          );
          expect(
            darkShad.primary,
            equals(darkTokens.brand),
            reason:
                'Dark palette ${palette.name} ShadColorScheme primary must match token brand',
          );
          expect(darkShad.background, equals(darkTokens.canvas));
          expect(darkShad.card, equals(darkTokens.surface));

          // Light verification
          final lightTokens = def.lightTokens;
          final lightShad = AppPaletteDefinition.buildShadColorScheme(
            palette,
            isDark: false,
          );
          final lightTheme = AppTheme.buildTheme(
            AppSettingsModel(themeMode: ThemeMode.light, palette: palette),
            brightness: Brightness.light,
          );

          expect(
            lightTokens.brand,
            equals(lightTheme.colorScheme.primary),
            reason:
                'Light palette ${palette.name} token brand must match ThemeData primary',
          );
          expect(
            lightShad.primary,
            equals(lightTokens.brand),
            reason:
                'Light palette ${palette.name} ShadColorScheme primary must match token brand',
          );
          expect(lightShad.background, equals(lightTokens.canvas));
          expect(lightShad.card, equals(lightTokens.surface));
        },
      );
    }
  });
}
