import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shellvibe/app/theme/app_theme.dart';
import 'package:shellvibe/app/theme/shellvibe_tokens.dart';
import 'package:shellvibe/app/theme/ui_font.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';

void main() {
  // google_fonts reaches for the asset bundle as soon as a family is asked
  // for, which needs a binding even though nothing here paints.
  TestWidgetsFlutterBinding.ensureInitialized();
  // The family name a Google font resolves to is deterministic, but asking for
  // one also kicks off a download. Tests do not get a network.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('UiFont', () {
    test('ids are unique, so a stored setting resolves to one font', () {
      final ids = kUiFonts.map((f) => f.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('exactly one font is bundled, and it leads the list', () {
      final bundled = kUiFonts
          .where((f) => f.source == UiFontSource.bundled)
          .toList();
      expect(bundled, hasLength(1));
      expect(kUiFonts.first, same(bundled.single));
      expect(bundled.single.family, ShellVibeTokens.uiFontFamily);
    });

    test('an unknown id falls back to the bundled default', () {
      expect(UiFont.of('NoSuchFont'), same(kUiFonts.first));
      expect(
        resolveUiFontFamily('NoSuchFont'),
        ShellVibeTokens.uiFontFamily,
      );
    });

    test('the bundled font resolves to its registered family', () {
      expect(resolveUiFontFamily('InterTight'), ShellVibeTokens.uiFontFamily);
    });

    test('a Google font resolves to a family of its own', () {
      final family = resolveUiFontFamily('IBMPlexSans');
      expect(family, isNotEmpty);
      expect(family, isNot(ShellVibeTokens.uiFontFamily));
    });
  });

  group('Theme', () {
    test('defaults to the bundled face in both halves of the shell', () {
      const settings = AppSettingsModel();
      expect(
        AppTheme.buildTheme(settings, brightness: Brightness.dark).textTheme
            .bodyMedium
            ?.fontFamily,
        ShellVibeTokens.uiFontFamily,
      );
      expect(
        AppTheme.buildShadTheme(settings, brightness: Brightness.dark)
            .textTheme
            .family,
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
        AppTheme.buildTheme(settings, brightness: Brightness.dark).textTheme
            .bodyMedium
            ?.fontFamily,
        expected,
      );
      expect(
        AppTheme.buildShadTheme(settings, brightness: Brightness.dark)
            .textTheme
            .family,
        expected,
      );
    });

    // A Google font that has not been fetched yet resolves to a family name
    // nothing can paint. Without the bundled face behind it the whole shell
    // would drop to the engine's fallback rather than to its own.
    test('keeps the bundled face behind a face that may not have loaded', () {
      const settings = AppSettingsModel(uiFontFamily: 'IBMPlexSans');

      expect(
        AppTheme.buildTheme(
          settings,
          brightness: Brightness.dark,
        ).textTheme.bodyMedium?.fontFamilyFallback,
        contains(ShellVibeTokens.uiFontFamily),
      );
      expect(
        AppTheme.buildShadTheme(settings, brightness: Brightness.dark)
            .textTheme
            .p
            .fontFamilyFallback,
        contains(ShellVibeTokens.uiFontFamily),
      );
    });
  });
}
