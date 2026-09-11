import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/app/theme/app_theme.dart';
import 'package:shellvibe/app/theme/shellvibe_tokens.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';

void main() {
  group('ThemeMode and Brightness Synchronization Tests', () {
    testWidgets('materialThemeBuilder respects explicit theme.brightness', (
      tester,
    ) async {
      const settings = AppSettingsModel(
        themeMode: ThemeMode.system,
        palette: AppPalette.dark,
      );

      late BuildContext capturedContext;

      await tester.pumpWidget(
        ShadApp(
          theme: AppTheme.buildShadTheme(
            settings,
            brightness: Brightness.light,
          ),
          darkTheme: AppTheme.buildShadTheme(
            settings,
            brightness: Brightness.dark,
          ),
          themeMode: ThemeMode.dark,
          materialThemeBuilder: (context, theme) =>
              AppTheme.buildTheme(settings, brightness: theme.brightness),
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(Theme.of(capturedContext).brightness, Brightness.dark);
      expect(ShadTheme.of(capturedContext).brightness, Brightness.dark);
      expect(
        ShellVibeTokens.resolve(capturedContext).canvas,
        ShellVibeTokens.dark.canvas,
      );
    });
  });
}
