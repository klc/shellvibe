import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/app/theme/app_theme.dart';
import 'package:terly2/app/theme/terly_tokens.dart';
import 'package:terly2/features/settings/domain/models/app_settings_model.dart';

void main() {
  test('Quiet Ops dark theme exposes the Terly token contract', () {
    final theme = AppTheme.buildTheme(const AppSettingsModel());
    final tokens = theme.extension<TerlyTokens>();

    expect(tokens, isNotNull);
    expect(tokens!.canvas, const Color(0xFF0B0E12));
    expect(tokens.brand, const Color(0xFF5EEAD4));
    expect(theme.scaffoldBackgroundColor, tokens.canvas);
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

  test('Light theme uses the matching Quiet Ops token values', () {
    final theme = AppTheme.buildTheme(
      const AppSettingsModel(themeMode: ThemeMode.light),
    );
    final tokens = theme.extension<TerlyTokens>();

    expect(tokens, TerlyTokens.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF5F7F9));
  });
}
