import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/theme/app_palette_definitions.dart';
import 'package:shellvibe/app/theme/app_theme.dart';
import 'package:shellvibe/app/theme/shellvibe_tokens.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Popovers, menus and their state layers must come from the palette, never
/// from shadcn's Slate or Material's neutral defaults.
void expectOverlaysFollowTokens(
  ShadColorScheme shad,
  ThemeData theme,
  ShellVibeTokens tokens,
) {
  expect(shad.popover, equals(tokens.surfaceRaised));
  expect(shad.popoverForeground, equals(tokens.textPrimary));
  expect(shad.input, equals(tokens.border));
  expect(shad.accentForeground, equals(tokens.textPrimary));
  expect(theme.popupMenuTheme.color, equals(tokens.surfaceRaised));
  expect(theme.focusColor, equals(tokens.brand.withValues(alpha: 0.12)));
  expect(theme.hoverColor, equals(tokens.textPrimary.withValues(alpha: 0.05)));

  // Roles Material widgets read when used with theme defaults.
  final scheme = theme.colorScheme;
  expect(scheme.onSurface, equals(tokens.textPrimary));
  expect(scheme.surfaceContainerLow, equals(tokens.surfaceRaised));
  expect(scheme.surfaceContainerHigh, equals(tokens.surfaceRaised));
  expect(scheme.outlineVariant, equals(tokens.border));
  expect(scheme.error, equals(tokens.danger));
  expect(scheme.inverseSurface, equals(tokens.textPrimary));
  expect(scheme.onInverseSurface, equals(tokens.canvas));

  final selectedLabel = theme.navigationBarTheme.labelTextStyle!.resolve({
    WidgetState.selected,
  });
  expect(selectedLabel!.color, equals(tokens.brandBright));
}

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
          expectOverlaysFollowTokens(darkShad, darkTheme, darkTokens);

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
          expectOverlaysFollowTokens(lightShad, lightTheme, lightTokens);
        },
      );
    }
  });
}
