import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/theme/app_palette_definitions.dart';
import 'package:shellvibe/app/theme/app_theme.dart';
import 'package:shellvibe/app/theme/shellvibe_tokens.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';

void main() {
  test('Nocturne dark theme exposes the ShellVibe token contract', () {
    // Graphite explicitly: the app ships on OLED now, and this test is the
    // contract for the graphite tokens, not for whichever palette is default.
    final theme = AppTheme.buildTheme(
      const AppSettingsModel(palette: AppPalette.dark),
    );
    final tokens = theme.extension<ShellVibeTokens>();

    expect(tokens, isNotNull);
    expect(tokens!.canvas, const Color(0xFF0A0B11));
    expect(tokens.surface, const Color(0xFF141726));
    expect(tokens.surfaceLow, const Color(0xFF0F111C));
    expect(tokens.terminalBg, const Color(0xFF101218));
    expect(tokens.brand, const Color(0xFF8B93FF));
    expect(tokens.brandInk, const Color(0xFF0B0D16));
    expect(theme.scaffoldBackgroundColor, tokens.canvas);
  });

  test('The app ships on OLED: true black canvas, no grey lift', () {
    final theme = AppTheme.buildTheme(const AppSettingsModel());
    final tokens = theme.extension<ShellVibeTokens>();

    expect(const AppSettingsModel().palette, AppPalette.oled);
    expect(tokens!.canvas, const Color(0xFF000000));
    expect(tokens.surfaceLow, const Color(0xFF000000));
    expect(theme.scaffoldBackgroundColor, tokens.canvas);
  });

  test('Nocturne panels keep a pixel-anchored gradient falloff', () {
    final tokens = ShellVibeTokens.dark;

    // A 400px panel reaches surfaceLow halfway down; an 800px one a quarter
    // of the way — the same 200px falloff either way.
    expect(
      (tokens.panelGradient(gradientExtent: 200, height: 400) as LinearGradient)
          .stops,
      [0, 0.5],
    );
    expect(
      (tokens.panelGradient(gradientExtent: 200, height: 800) as LinearGradient)
          .stops,
      [0, 0.25],
    );
  });

  test('Terminal font choice does not change application UI typography', () {
    final defaultTheme = AppTheme.buildTheme(const AppSettingsModel());
    final customTerminalFontTheme = AppTheme.buildTheme(
      const AppSettingsModel(fontFamily: 'FiraCode'),
    );

    expect(customTerminalFontTheme.textTheme, defaultTheme.textTheme);
    expect(
      customTerminalFontTheme.textTheme.bodyMedium?.fontFamily,
      defaultTheme.textTheme.bodyMedium?.fontFamily,
    );
  });

  test('Every ramp step is set in the bundled interface face', () {
    final theme = AppTheme.buildTheme(const AppSettingsModel());
    final ramp = <String, TextStyle?>{
      'displaySmall': theme.textTheme.displaySmall,
      'headlineSmall': theme.textTheme.headlineSmall,
      'titleLarge': theme.textTheme.titleLarge,
      'titleMedium': theme.textTheme.titleMedium,
      'titleSmall': theme.textTheme.titleSmall,
      'bodyLarge': theme.textTheme.bodyLarge,
      'bodyMedium': theme.textTheme.bodyMedium,
      'bodySmall': theme.textTheme.bodySmall,
      'labelLarge': theme.textTheme.labelLarge,
      'labelMedium': theme.textTheme.labelMedium,
      'labelSmall': theme.textTheme.labelSmall,
    };

    for (final step in ramp.entries) {
      expect(
        step.value?.fontFamily,
        ShellVibeTokens.uiFontFamily,
        reason: '${step.key} falls back to the platform font',
      );
    }
    // The interface face and the terminal face stay separate contracts.
    expect(ShellVibeTokens.uiFontFamily, isNot(ShellVibeTokens.monoFontFamily));
  });

  test('Light theme uses the matching Nocturne token values', () {
    final theme = AppTheme.buildTheme(
      const AppSettingsModel(
        themeMode: ThemeMode.light,
        palette: AppPalette.dark,
      ),
    );
    final tokens = theme.extension<ShellVibeTokens>();

    expect(tokens, ShellVibeTokens.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF2F4F8));
  });

  test('Every palette keeps its terminal chrome light in daylight', () {
    // These two used to be copied from the dark contract and never overridden,
    // which painted the pane header and the bottom of the active tab's
    // gradient near-black on an otherwise white app.
    for (final palette in AppPalette.values) {
      final tokens = AppPaletteDefinition.forPalette(palette).lightTokens;

      for (final entry in {
        'terminalBg': tokens.terminalBg,
        'terminalChrome': tokens.terminalChrome,
      }.entries) {
        expect(
          entry.value.computeLuminance(),
          greaterThan(0.5),
          reason: '${palette.name} light ${entry.key} is a dark colour',
        );
      }
    }
  });
}
