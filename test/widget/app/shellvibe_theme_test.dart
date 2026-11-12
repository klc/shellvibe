import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/theme/app_palette_definitions.dart';
import 'package:shellvibe/app/theme/app_theme.dart';
import 'package:shellvibe/app/theme/shellvibe_tokens.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_palette_data.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_palette.dart';

void main() {
  test('Nocturne dark theme exposes the ShellVibe token contract', () {
    // ShellVibe Amber explicitly — it is also the default the app ships on —
    // contract for the graphite tokens, not for whichever palette is default.
    final theme = AppTheme.buildTheme(
      const AppSettingsModel(
        themeMode: ThemeMode.dark,
        palette: AppPalette.dark,
      ),
    );
    final tokens = theme.extension<ShellVibeTokens>();

    expect(tokens, isNotNull);
    expect(tokens!.canvas, const Color(0xFF141414));
    expect(tokens.surface, const Color(0xFF141414));
    expect(tokens.surfaceLow, const Color(0xFF101010));
    expect(tokens.terminalBg, const Color(0xFF101010));
    expect(tokens.brand, const Color(0xFFE5A23C));
    expect(tokens.brandInk, const Color(0xFF17130A));
    expect(theme.scaffoldBackgroundColor, tokens.canvas);
  });

  test('The app ships on ShellVibe Amber, terminal matched to it', () {
    const defaults = AppSettingsModel();
    final theme = AppTheme.buildTheme(
      const AppSettingsModel(themeMode: ThemeMode.dark),
    );
    final tokens = theme.extension<ShellVibeTokens>();

    expect(defaults.palette, AppPalette.dark);
    expect(AppPalette.dark.label, 'ShellVibe Amber');
    expect(tokens!.canvas, const Color(0xFF141414));
    expect(tokens.brand, const Color(0xFFE5A23C));
    expect(theme.scaffoldBackgroundColor, tokens.canvas);
    // "Match App Theme" lands on the scheme of the same name in the dark.
    expect(
      defaults.resolvedTerminalPalette(Brightness.dark),
      TerminalPalette.nocturne,
    );
    expect(
      TerminalPaletteData.of(TerminalPalette.nocturne).label,
      'ShellVibe Amber',
    );
  });

  test('Terminal font choice does not change application UI typography', () {
    final defaultTheme = AppTheme.buildTheme(
      const AppSettingsModel(themeMode: ThemeMode.dark),
    );
    final customTerminalFontTheme = AppTheme.buildTheme(
      const AppSettingsModel(themeMode: ThemeMode.dark, fontFamily: 'FiraCode'),
    );

    expect(customTerminalFontTheme.textTheme, defaultTheme.textTheme);
    expect(
      customTerminalFontTheme.textTheme.bodyMedium?.fontFamily,
      defaultTheme.textTheme.bodyMedium?.fontFamily,
    );
  });

  test('Every ramp step is set in the bundled interface face', () {
    final theme = AppTheme.buildTheme(
      const AppSettingsModel(themeMode: ThemeMode.dark),
    );
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
    expect(theme.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
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
