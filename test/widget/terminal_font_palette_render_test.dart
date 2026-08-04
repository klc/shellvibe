import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/features/terminal/domain/models/terminal_font.dart';
import 'package:terly2/features/terminal/domain/models/terminal_palette_data.dart';
import 'package:terly2/features/terminal/presentation/utils/terminal_font_resolver.dart';
import 'package:xterm2/xterm.dart';

/// Bundled Nerd Font assets referenced by pubspec, keyed by font id.
const _kNerdFontAssets = <String, String>{
  'JetBrainsMonoNF': 'assets/fonts/nerd/JetBrainsMonoNerdFontMono-Regular.ttf',
  'FiraCodeNF': 'assets/fonts/nerd/FiraCodeNerdFontMono-Regular.ttf',
  'MesloLGMNF': 'assets/fonts/nerd/MesloLGMNerdFontMono-Regular.ttf',
  'Hack': 'assets/fonts/nerd/HackNerdFontMono-Regular.ttf',
  'CaskaydiaCoveNF': 'assets/fonts/nerd/CaskaydiaCoveNerdFontMono-Regular.ttf',
  'UbuntuMonoNF': 'assets/fonts/nerd/UbuntuMonoNerdFontMono-Regular.ttf',
  'SauceCodeProNF': 'assets/fonts/nerd/SauceCodeProNerdFontMono-Regular.ttf',
  kSymbolsNerdFontFamily:
      'assets/fonts/nerd/SymbolsNerdFontMono-Regular.ttf',
};

/// Boots [TerminalView] with a given theme/font and writes representative
/// shell output including Nerd Font Private-Use-Area glyphs. Any layout or
/// shaping exception fails the test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled Nerd Font TTF assets are present', (tester) async {
    for (final entry in _kNerdFontAssets.entries) {
      final data = await rootBundle.load(entry.value);
      expect(data.lengthInBytes, greaterThan(1_000_000),
          reason: '${entry.key} asset too small');
    }
  });

  testWidgets(
      'every palette renders in TerminalView with a Nerd Font family',
      (WidgetTester tester) async {
    for (final palette in kTerminalPalettes) {
      final terminal = Terminal(maxLines: 500);

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 720,
              height: 240,
              child: TerminalView(
                terminal,
                theme: palette.theme,
                textStyle: TerminalStyle(
                  fontFamily: 'JetBrainsMono Nerd Font Mono',
                  fontFamilyFallback: kTerminalFontFamilyFallback,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      terminal.write('The quick brown fox 12345\n');
      // Powerline separator, devicon, codicon — Nerd Font PUA codepoints.
      terminal.write('\u{E0B0}\u{F313}\u{F489} nerd-font smoke\n');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        tester.takeException(),
        isNull,
        reason: 'palette ${palette.label} failed to render',
      );

      // Tear down between iterations so per-terminal state (focus, timers)
      // cannot leak into the next palette.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('font resolver output works as a TextStyle family',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Text(
          kFontPreviewText,
          style: TextStyle(
            fontFamily: resolveTerminalFontFamily('JetBrainsMonoNF'),
            fontFamilyFallback: kTerminalFontFamilyFallback,
            fontSize: 16,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}