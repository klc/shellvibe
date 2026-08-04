import 'package:google_fonts/google_fonts.dart';

import '../../domain/models/terminal_font.dart';

/// Resolves a stored font id (settings.fontFamily) to a family name the
/// terminal TextStyle can use directly.
///
/// Google Fonts families resolve through the `google_fonts` package (fetched
/// from the CDN on first use, then cached). Bundled Nerd Fonts and system
/// fonts are already registered family names.
String resolveTerminalFontFamily(String fontId) {
  final font = TerminalFont.of(fontId);
  switch (font.source) {
    case TerminalFontSource.googleFonts:
      try {
        return GoogleFonts.getFont(font.googleFontsName!).fontFamily ??
            font.googleFontsName!;
      } catch (_) {
        // Unknown family — let Flutter's engine fall back.
        return font.googleFontsName!;
      }
    case TerminalFontSource.bundledNerdFont:
    case TerminalFontSource.system:
      return font.familyName!;
  }
}

/// Fallback chain for terminal glyphs the primary font lacks: Nerd Font
/// symbols first, then the xterm2 default stack (CJK, emoji, …).
const kTerminalFontFamilyFallback = <String>[
  kSymbolsNerdFontFamily,
  'SF Mono',
  'Menlo',
  'Monaco',
  'Cascadia Mono',
  'Consolas',
  'Liberation Mono',
  'DejaVu Sans Mono',
  'Courier New',
  'Noto Sans Mono CJK SC',
  'Noto Sans Mono CJK TC',
  'Noto Sans Mono CJK KR',
  'Noto Sans Mono CJK JP',
  'Noto Sans Mono CJK HK',
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Noto Color Emoji',
  'Segoe UI Symbol',
  'monospace',
  'sans-serif',
];

/// Sample text for the Settings font preview; exercises ligatures, slashes,
/// and common prompt glyphs.
const kFontPreviewText = 'AaBbCc 123 → == != => \$ ~';