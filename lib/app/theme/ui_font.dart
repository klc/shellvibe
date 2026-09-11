import 'package:google_fonts/google_fonts.dart';

import 'shellvibe_tokens.dart';

/// How an interface font is resolved at runtime.
enum UiFontSource {
  /// Family bundled in `assets/fonts/ui` and registered in pubspec. Resolves
  /// offline and is painted on the first frame.
  bundled,

  /// Family fetched on first use from the Google Fonts CDN by the
  /// `google_fonts` package, then cached on disk. The shell draws in the
  /// bundled face until that download lands and repaints once it does, so the
  /// choice costs a network round trip exactly once per family.
  googleFonts,
}

/// A font selectable for the application interface.
///
/// There is deliberately no "system font" entry. Flutter reads a null family
/// as the platform default, but shadcn_ui reads it as its own bundled Geist —
/// the Material half of the shell and the Shad half would settle on different
/// faces and the setting would not mean what it says.
class UiFont {
  const UiFont({
    required this.id,
    required this.label,
    required this.source,
    required this.family,
  });

  /// Stable storage key (`settings.uiFontFamily`). Never rename an existing
  /// id — saved settings reference it.
  final String id;

  /// Display label in Settings.
  final String label;

  final UiFontSource source;

  /// Registered family name for [UiFontSource.bundled]; the Google Fonts
  /// display name for [UiFontSource.googleFonts].
  final String family;

  static UiFont of(String fontId) =>
      kUiFonts.firstWhere((f) => f.id == fontId, orElse: () => kUiFonts.first);
}

/// Every selectable interface font, in Settings dropdown order: the bundled
/// default first, the rest alphabetical by label.
///
/// The list is grotesques and neo-grotesques only. A terminal client's chrome
/// is labels, paths and numbers at 12–14px, which is where a display or
/// humanist face stops being legible and starts being decoration.
const kUiFonts = <UiFont>[
  UiFont(
    id: 'InterTight',
    label: 'Inter Tight',
    source: UiFontSource.bundled,
    family: ShellVibeTokens.uiFontFamily,
  ),
  UiFont(
    id: 'DMSans',
    label: 'DM Sans',
    source: UiFontSource.googleFonts,
    family: 'DM Sans',
  ),
  UiFont(
    id: 'IBMPlexSans',
    label: 'IBM Plex Sans',
    source: UiFontSource.googleFonts,
    family: 'IBM Plex Sans',
  ),
  UiFont(
    id: 'Inter',
    label: 'Inter',
    source: UiFontSource.googleFonts,
    family: 'Inter',
  ),
  UiFont(
    id: 'Lato',
    label: 'Lato',
    source: UiFontSource.googleFonts,
    family: 'Lato',
  ),
  UiFont(
    id: 'Manrope',
    label: 'Manrope',
    source: UiFontSource.googleFonts,
    family: 'Manrope',
  ),
  UiFont(
    id: 'NunitoSans',
    label: 'Nunito Sans',
    source: UiFontSource.googleFonts,
    family: 'Nunito Sans',
  ),
  UiFont(
    id: 'Roboto',
    label: 'Roboto',
    source: UiFontSource.googleFonts,
    family: 'Roboto',
  ),
  UiFont(
    id: 'SourceSans3',
    label: 'Source Sans 3',
    source: UiFontSource.googleFonts,
    family: 'Source Sans 3',
  ),
  UiFont(
    id: 'WorkSans',
    label: 'Work Sans',
    source: UiFontSource.googleFonts,
    family: 'Work Sans',
  ),
];

/// What the shell falls back to when the chosen family has no glyph — or,
/// for a Google font, has not been fetched yet.
///
/// Without this a font picked while offline leaves the whole interface on the
/// engine's own fallback until the download lands, which is a worse face than
/// the one the app already ships with.
const kUiFontFamilyFallback = <String>[ShellVibeTokens.uiFontFamily];

/// Resolves a stored font id (`settings.uiFontFamily`) to a family name a
/// [TextStyle] can use directly.
///
/// Both halves of the shell call this with the same id, which is what keeps
/// Material's widgets and Shad's drawing in one face.
String resolveUiFontFamily(String fontId) {
  final font = UiFont.of(fontId);
  switch (font.source) {
    case UiFontSource.bundled:
      return font.family;
    case UiFontSource.googleFonts:
      try {
        return GoogleFonts.getFont(font.family).fontFamily ?? font.family;
      } catch (_) {
        // A family the package does not know would leave the whole shell on
        // the engine's fallback. The bundled face is the better answer.
        return ShellVibeTokens.uiFontFamily;
      }
  }
}
