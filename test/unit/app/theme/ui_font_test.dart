import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/theme/app_theme.dart';
import 'package:shellvibe/app/theme/shellvibe_tokens.dart';
import 'package:shellvibe/app/theme/ui_font.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';

void main() {
  group('UiFont', () {
    test('ids are unique, so a stored setting resolves to one font', () {
      final ids = kUiFonts.map((f) => f.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('the default face leads the list', () {
      expect(kUiFonts.first.family, ShellVibeTokens.uiFontFamily);
    });

    test('an unknown id falls back to the bundled default', () {
      expect(UiFont.of('NoSuchFont'), same(kUiFonts.first));
      expect(resolveUiFontFamily('NoSuchFont'), ShellVibeTokens.uiFontFamily);
    });

    test('the default font resolves to its registered family', () {
      expect(resolveUiFontFamily('InterTight'), ShellVibeTokens.uiFontFamily);
    });

    // The family, not a per-weight variant of it: a theme set in a family
    // that holds one weight draws every bold label at regular weight.
    test('an optional font resolves to its registered family', () {
      expect(resolveUiFontFamily('IBMPlexSans'), 'IBM Plex Sans');
    });
  });

  group('Theme', () {
    test('defaults to the bundled face in both halves of the shell', () {
      const settings = AppSettingsModel();
      expect(
        AppTheme.buildTheme(
          settings,
          brightness: Brightness.dark,
        ).textTheme.bodyMedium?.fontFamily,
        ShellVibeTokens.uiFontFamily,
      );
      expect(
        AppTheme.buildShadTheme(
          settings,
          brightness: Brightness.dark,
        ).textTheme.family,
        ShellVibeTokens.uiFontFamily,
      );
    });

    // Material draws the shell's screens and Shad draws its inputs, selects
    // and popovers from separate text themes. A setting that moved only one
    // of them would split the interface across two faces.
    test('carries a chosen face into both halves of the shell', () {
      const settings = AppSettingsModel(uiFontFamily: 'IBMPlexSans');
      final expected = resolveUiFontFamily('IBMPlexSans');

      expect(
        AppTheme.buildTheme(
          settings,
          brightness: Brightness.dark,
        ).textTheme.bodyMedium?.fontFamily,
        expected,
      );
      expect(
        AppTheme.buildShadTheme(
          settings,
          brightness: Brightness.dark,
        ).textTheme.family,
        expected,
      );
    });

    // A glyph the chosen face lacks should land on the face the rest of the
    // app is drawn in, not on the engine's own fallback.
    test('keeps the default face behind a chosen one', () {
      const settings = AppSettingsModel(uiFontFamily: 'IBMPlexSans');

      expect(
        AppTheme.buildTheme(
          settings,
          brightness: Brightness.dark,
        ).textTheme.bodyMedium?.fontFamilyFallback,
        contains(ShellVibeTokens.uiFontFamily),
      );
      expect(
        AppTheme.buildShadTheme(
          settings,
          brightness: Brightness.dark,
        ).textTheme.p.fontFamilyFallback,
        contains(ShellVibeTokens.uiFontFamily),
      );
    });
  });
}
