import '../../domain/models/terminal_font.dart';

/// Resolves a stored font id (settings.fontFamily) to a family name the
/// terminal TextStyle can use directly.
///
/// Every non-system face is bundled and registered in pubspec under this
/// name; a system family the OS lacks falls through to
/// [kTerminalFontFamilyFallback].
String resolveTerminalFontFamily(String fontId) =>
    TerminalFont.of(fontId).familyName;

/// Fallback chain for terminal glyphs the primary font lacks: Nerd Font
/// symbols first, then the xterm3 default stack (CJK, symbols, emoji, …).
///
/// Monochrome symbol families deliberately precede the color emoji families.
/// Codepoints such as U+23F8 PAUSE default to text presentation, and no
/// monospace font on macOS carries them — without a text-presentation font
/// ahead of it, Apple Color Emoji claims the glyph and a status line meant to
/// read as two thin bars renders as a colored pill.
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
  // Text-presentation symbol coverage, per platform: STIX Two Math ships with
  // macOS and is the only system family there with Miscellaneous Technical.
  'STIX Two Math',
  'Segoe UI Symbol',
  'Noto Sans Symbols 2',
  'Noto Sans Symbols',
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Noto Color Emoji',
  'monospace',
  'sans-serif',
];

/// Sample text for the Settings font preview; exercises ligatures, slashes,
/// and common prompt glyphs.
const kFontPreviewText = 'AaBbCc 123 → == != => \$ ~';
