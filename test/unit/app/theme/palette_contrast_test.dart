import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/theme/app_palette_definitions.dart';
import 'package:shellvibe/app/theme/app_theme.dart';
import 'package:shellvibe/app/theme/shellvibe_tokens.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';

/// WCAG 2.1 relative luminance.
double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// WCAG 2.1 contrast ratio, 1.0 (identical) to 21.0 (black on white).
double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// AA for body copy.
const double _kBodyMinimum = 4.5;

/// AA for large text and non-text UI. Only the decorative bottom of the text
/// ramp is held to this — section labels and meta, never a sentence.
const double _kDecorativeMinimum = 3.0;

void main() {
  group('Palette contrast', () {
    void expectRatio(
      String label,
      Color foreground,
      Color background,
      double minimum,
    ) {
      final ratio = contrastRatio(foreground, background);
      expect(
        ratio,
        greaterThanOrEqualTo(minimum),
        reason:
            '$label is ${ratio.toStringAsFixed(2)}:1, below the $minimum:1 floor',
      );
    }

    for (final palette in AppPalette.values) {
      for (final isDark in const [true, false]) {
        final mode = isDark ? 'dark' : 'light';

        test('${palette.name} $mode keeps its text ramp readable', () {
          final definition = AppPaletteDefinition.forPalette(palette);
          final ShellVibeTokens tokens = isDark
              ? definition.darkTokens
              : definition.lightTokens;
          final where = '${palette.name} $mode';

          expectRatio(
            '$where textPrimary on canvas',
            tokens.textPrimary,
            tokens.canvas,
            _kBodyMinimum,
          );
          expectRatio(
            '$where textSecondary on surface',
            tokens.textSecondary,
            tokens.surface,
            _kBodyMinimum,
          );
          expectRatio(
            '$where textMuted on surface',
            tokens.textMuted,
            tokens.surface,
            _kBodyMinimum,
          );
          expectRatio(
            '$where textSubtle on surface',
            tokens.textSubtle,
            tokens.surface,
            _kDecorativeMinimum,
          );
        });

        test('${palette.name} $mode keeps its brand legible', () {
          final definition = AppPaletteDefinition.forPalette(palette);
          final tokens = isDark
              ? definition.darkTokens
              : definition.lightTokens;
          final where = '${palette.name} $mode';

          // A primary button: brandInk is the label, brand the fill.
          expectRatio(
            '$where brandInk on brand',
            tokens.brandInk,
            tokens.brand,
            _kBodyMinimum,
          );
          // The same label sits on the raised gradient, whose darkest stop is
          // the one that can fail.
          expectRatio(
            '$where brandInk on brandGradientTop',
            tokens.brandInk,
            tokens.brandGradientTop,
            _kDecorativeMinimum,
          );
          // Danger states are read under pressure; they get no exemption.
          expectRatio(
            '$where dangerMutedText on dangerMutedSurface',
            tokens.dangerMutedText,
            tokens.dangerMutedSurface,
            _kBodyMinimum,
          );
        });

        // Material derives its own on-colours from the seed. Tokens being
        // right does not make those right, and every Material widget in the
        // app reads them rather than the tokens.
        test('${palette.name} $mode derives legible Material on-colours', () {
          final scheme = AppTheme.buildTheme(
            AppSettingsModel(
              themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
              palette: palette,
            ),
            brightness: isDark ? Brightness.dark : Brightness.light,
          ).colorScheme;
          final where = '${palette.name} $mode';

          expectRatio(
            '$where onSurface on surface',
            scheme.onSurface,
            scheme.surface,
            _kBodyMinimum,
          );
          expectRatio(
            '$where onPrimary on primary',
            scheme.onPrimary,
            scheme.primary,
            _kBodyMinimum,
          );
          expectRatio(
            '$where onSecondary on secondary',
            scheme.onSecondary,
            scheme.secondary,
            _kBodyMinimum,
          );
          expectRatio(
            '$where onError on error',
            scheme.onError,
            scheme.error,
            _kBodyMinimum,
          );
        });
      }
    }
  });
}
