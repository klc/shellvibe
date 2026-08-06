/// How a terminal font is resolved at runtime.
enum TerminalFontSource {
  /// Family fetched on first use from the Google Fonts CDN by the
  /// `google_fonts` package and cached on disk; requires network once.
  /// Bundled Nerd Fonts below are the always-offline options.
  googleFonts,

  /// Nerd Font TTF bundled in `assets/fonts/nerd` and registered in pubspec.
  bundledNerdFont,

  /// OS/system font referenced by family name; missing families fall back.
  system,
}

/// A font selectable for terminal sessions.
class TerminalFont {
  const TerminalFont({
    required this.id,
    required this.label,
    required this.source,
    this.googleFontsName,
    this.familyName,
  });

  /// Stable storage key (`settings.fontFamily`). Never rename an existing id —
  /// saved settings reference it.
  final String id;

  /// Display label in Settings.
  final String label;

  final TerminalFontSource source;

  /// Google Fonts display name for [google_fonts] lookups (source googleFonts).
  final String? googleFontsName;

  /// Registered family name used directly in a TextStyle (bundledNerdFont /
  /// system sources).
  final String? familyName;

  static TerminalFont of(String fontId) =>
      kTerminalFonts.firstWhere(
        (f) => f.id == fontId,
        orElse: () => kTerminalFonts.first,
      );
}

/// Symbols Nerd Font Mono — registered in pubspec; every terminal session
/// falls back to it so prompt icons (powerline, devicons, …) render even with
/// non-Nerd Fonts. Matches the family name xterm3 already lists in its
/// default `fontFamilyFallback`.
const kSymbolsNerdFontFamily = 'Symbols Nerd Font Mono';

/// All selectable fonts, in Settings dropdown order: the default
/// (Roboto Mono) first, the rest sorted alphabetically by label.
const kTerminalFonts = <TerminalFont>[
  TerminalFont(
    id: 'RobotoMono',
    label: 'Roboto Mono',
    source: TerminalFontSource.googleFonts,
    googleFontsName: 'Roboto Mono',
  ),
  TerminalFont(
    id: 'AnonymousPro',
    label: 'Anonymous Pro',
    source: TerminalFontSource.googleFonts,
    googleFontsName: 'Anonymous Pro',
  ),
  TerminalFont(
    id: 'CascadiaCode',
    label: 'Cascadia Code',
    source: TerminalFontSource.googleFonts,
    googleFontsName: 'Cascadia Code',
  ),
  TerminalFont(
    id: 'CaskaydiaCoveNF',
    label: 'Cascadia Code Nerd Font',
    source: TerminalFontSource.bundledNerdFont,
    familyName: 'CaskaydiaCove Nerd Font Mono',
  ),
  TerminalFont(
    id: 'Courier',
    label: 'Courier',
    source: TerminalFontSource.system,
    familyName: 'Courier',
  ),
  TerminalFont(
    id: 'FiraCode',
    label: 'Fira Code',
    source: TerminalFontSource.googleFonts,
    googleFontsName: 'Fira Code',
  ),
  TerminalFont(
    id: 'FiraCodeNF',
    label: 'Fira Code Nerd Font',
    source: TerminalFontSource.bundledNerdFont,
    familyName: 'FiraCode Nerd Font Mono',
  ),
  TerminalFont(
    id: 'FiraMono',
    label: 'Fira Mono',
    source: TerminalFontSource.googleFonts,
    googleFontsName: 'Fira Mono',
  ),
  TerminalFont(
    id: 'Hack',
    label: 'Hack Nerd Font',
    source: TerminalFontSource.bundledNerdFont,
    familyName: 'Hack Nerd Font Mono',
  ),
  TerminalFont(
    id: 'IBMPlexMono',
    label: 'IBM Plex Mono',
    source: TerminalFontSource.googleFonts,
    googleFontsName: 'IBM Plex Mono',
  ),
  TerminalFont(
    id: 'Inconsolata',
    label: 'Inconsolata',
    source: TerminalFontSource.googleFonts,
    googleFontsName: 'Inconsolata',
  ),
  TerminalFont(
    id: 'Inter',
    label: 'Inter',
    source: TerminalFontSource.googleFonts,
    googleFontsName: 'Inter',
  ),
  TerminalFont(
    id: 'JetBrainsMono',
    label: 'JetBrains Mono',
    source: TerminalFontSource.googleFonts,
    googleFontsName: 'JetBrains Mono',
  ),
  TerminalFont(
    id: 'JetBrainsMonoNF',
    label: 'JetBrains Mono Nerd Font',
    source: TerminalFontSource.bundledNerdFont,
    familyName: 'JetBrainsMono Nerd Font Mono',
  ),
  TerminalFont(
    id: 'KodeMono',
    label: 'Kode Mono',
    source: TerminalFontSource.googleFonts,
    googleFontsName: 'Kode Mono',
  ),
  TerminalFont(
    id: 'MesloLGMNF',
    label: 'MesloLGM Nerd Font',
    source: TerminalFontSource.bundledNerdFont,
    familyName: 'MesloLGM Nerd Font Mono',
  ),
  TerminalFont(
    id: 'ShareTechMono',
    label: 'Share Tech Mono',
    source: TerminalFontSource.googleFonts,
    googleFontsName: 'Share Tech Mono',
  ),

  // --- Bundled Nerd Fonts (Mono variant: every glyph single-cell wide, so
  // grid alignment holds inside xterm3, which treats PUA as width 1) ---
  TerminalFont(
    id: 'SourceCodePro',
    label: 'Source Code Pro',
    source: TerminalFontSource.googleFonts,
    googleFontsName: 'Source Code Pro',
  ),
  TerminalFont(
    id: 'SauceCodeProNF',
    label: 'Source Code Pro Nerd Font',
    source: TerminalFontSource.bundledNerdFont,
    familyName: 'SauceCodePro Nerd Font Mono',
  ),

  // --- System ---
  TerminalFont(
    id: 'SpaceMono',
    label: 'Space Mono',
    source: TerminalFontSource.googleFonts,
    googleFontsName: 'Space Mono',
  ),
  TerminalFont(
    id: 'UbuntuMono',
    label: 'Ubuntu Mono',
    source: TerminalFontSource.googleFonts,
    googleFontsName: 'Ubuntu Mono',
  ),
  TerminalFont(
    id: 'UbuntuMonoNF',
    label: 'Ubuntu Mono Nerd Font',
    source: TerminalFontSource.bundledNerdFont,
    familyName: 'UbuntuMono Nerd Font Mono',
  ),
];