import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_font.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_palette.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_palette_data.dart';
import 'package:shellvibe/features/terminal/presentation/utils/terminal_font_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TerminalPalette registry', () {
    // matchApp names a rule, not colours: it is resolved to one of these
    // before any lookup, so it has no registry entry of its own.
    final schemes = TerminalPalette.values.where(
      (value) => value != TerminalPalette.matchApp,
    );

    test('covers every scheme exactly once', () {
      final palettes = kTerminalPalettes.map((p) => p.palette).toList();
      expect(palettes, hasLength(schemes.length));
      expect(palettes.toSet(), hasLength(palettes.length));
      for (final value in schemes) {
        expect(palettes, contains(value));
      }
      expect(palettes, isNot(contains(TerminalPalette.matchApp)));
    });

    test('lookup returns the registered entry for every palette', () {
      for (final value in schemes) {
        expect(TerminalPaletteData.of(value).palette, value);
      }
    });

    test('every entry has a non-empty, unique label', () {
      final labels = kTerminalPalettes.map((p) => p.label).toList();
      expect(labels, hasLength(kTerminalPalettes.length));
      expect(labels.every((l) => l.isNotEmpty), isTrue);
      expect(labels.toSet(), hasLength(labels.length));
    });

    test('stored settings decode to a known theme (backward compat)', () {
      // Values saved by older builds must keep resolving after new themes
      // were appended.
      for (final name in ['dark', 'cyberpunk', 'monokai', 'catppuccin']) {
        final value = TerminalPalette.values.firstWhere(
          (e) => e.name == name,
          orElse: () => fail('missing legacy palette $name'),
        );
        expect(TerminalPaletteData.themeOf(value), isNotNull);
      }
    });

    test(
      'matchApp resolves every app palette to a scheme of its brightness',
      () {
        for (final palette in AppPalette.values) {
          final settings = AppSettingsModel(palette: palette);
          for (final brightness in Brightness.values) {
            final resolved = settings.resolvedTerminalPalette(brightness);
            expect(resolved, isNot(TerminalPalette.matchApp));
            expect(
              TerminalPaletteData.of(resolved).isLight,
              brightness == Brightness.light,
              reason: '${palette.name} ${brightness.name} -> ${resolved.name}',
            );
          }
        }
      },
    );

    test('matchApp pairs a palette with its own terminal scheme', () {
      const gruvbox = AppSettingsModel(palette: AppPalette.gruvbox);
      expect(
        gruvbox.resolvedTerminalPalette(Brightness.light),
        TerminalPalette.gruvboxLight,
      );
      expect(
        gruvbox.resolvedTerminalPalette(Brightness.dark),
        TerminalPalette.gruvboxDark,
      );
    });

    test('an explicit scheme is kept whatever the app theme', () {
      const settings = AppSettingsModel(
        palette: AppPalette.gruvbox,
        terminalPalette: TerminalPalette.oled,
      );
      for (final brightness in Brightness.values) {
        expect(
          settings.resolvedTerminalPalette(brightness),
          TerminalPalette.oled,
        );
      }
    });

    test('new and unreadable settings follow the app; stored choices stay', () {
      expect(
        const AppSettingsModel().terminalPalette,
        TerminalPalette.matchApp,
      );
      expect(
        AppSettingsModel.fromJson(const {}).terminalPalette,
        TerminalPalette.matchApp,
      );
      expect(
        AppSettingsModel.fromJson(const {
          'terminalPalette': 'oled',
        }).terminalPalette,
        TerminalPalette.oled,
      );
    });

    test('appending new enum values does not shift existing names', () {
      expect(TerminalPalette.dark.name, 'dark');
      expect(TerminalPalette.monokai.name, 'monokai');
      expect(TerminalPalette.cyberpunk.name, 'cyberpunk');
      expect(TerminalPalette.oneLight.name, 'oneLight');
    });
  });

  group('TerminalFont registry', () {
    test('ids are unique and every entry resolves back to itself', () {
      final ids = kTerminalFonts.map((f) => f.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final font in kTerminalFonts) {
        expect(TerminalFont.of(font.id), same(font));
      }
    });

    test('unknown stored id falls back to the default font', () {
      expect(TerminalFont.of('__never_saved__').id, kTerminalFonts.first.id);
    });

    test('includes legacy Hack id bound to the bundled Nerd Font', () {
      final hack = TerminalFont.of('Hack');
      expect(hack.source, TerminalFontSource.bundledNerdFont);
      expect(hack.familyName, 'Hack Nerd Font Mono');
    });

    // PRIVACY.md promises the defaults make no network request. The default
    // terminal face used to be fetched from the Google Fonts CDN.
    test('the default font is bundled', () {
      expect(kTerminalFonts.first.source, TerminalFontSource.bundled);
    });
  });

  group('resolveTerminalFontFamily', () {
    test('resolves bundled Nerd Font ids to their registered family', () {
      expect(
        resolveTerminalFontFamily('JetBrainsMonoNF'),
        'JetBrainsMono Nerd Font Mono',
      );
      expect(resolveTerminalFontFamily('Hack'), 'Hack Nerd Font Mono');
    });

    test('system font resolves to its family name', () {
      expect(resolveTerminalFontFamily('Courier'), 'Courier');
    });

    test('bundled Google Fonts ids resolve to their registered family', () {
      expect(resolveTerminalFontFamily('RobotoMono'), 'Roboto Mono');
      expect(resolveTerminalFontFamily('JetBrainsMono'), 'JetBrains Mono');
    });

    test('symbols fallback family matches the terminal fallback chain', () {
      expect(kTerminalFontFamilyFallback.first, kSymbolsNerdFontFamily);
    });
  });
}
