import 'shellvibe_tokens.dart';

/// A font selectable for the application interface.
///
/// Every entry is bundled in `assets/fonts/ui` and registered in pubspec at
/// the weights the theme sets, so a choice resolves offline and paints on the
/// first frame. Nothing here is fetched: a font picked in Settings makes no
/// network request.
///
/// There is deliberately no "system font" entry. Flutter reads a null family
/// as the platform default, but shadcn_ui reads it as its own bundled Geist —
/// the Material half of the shell and the Shad half would settle on different
/// faces and the setting would not mean what it says.
class UiFont {
  const UiFont({required this.id, required this.label, required this.family});

  /// Stable storage key (`settings.uiFontFamily`). Never rename an existing
  /// id — saved settings reference it.
  final String id;

  /// Display label in Settings.
  final String label;

  /// Family name registered in pubspec.
  final String family;

  static UiFont of(String fontId) =>
      kUiFonts.firstWhere((f) => f.id == fontId, orElse: () => kUiFonts.first);
}

/// Every selectable interface font, in Settings dropdown order: the default
/// first, the rest alphabetical by label.
///
/// The list is grotesques and neo-grotesques only. A terminal client's chrome
/// is labels, paths and numbers at 12–14px, which is where a display or
/// humanist face stops being legible and starts being decoration.
const kUiFonts = <UiFont>[
  UiFont(
    id: 'InterTight',
    label: 'Inter Tight',
    family: ShellVibeTokens.uiFontFamily,
  ),
  UiFont(id: 'DMSans', label: 'DM Sans', family: 'DM Sans'),
  UiFont(id: 'IBMPlexSans', label: 'IBM Plex Sans', family: 'IBM Plex Sans'),
  UiFont(id: 'Inter', label: 'Inter', family: 'Inter'),
  UiFont(id: 'Lato', label: 'Lato', family: 'Lato'),
  UiFont(id: 'Manrope', label: 'Manrope', family: 'Manrope'),
  UiFont(id: 'NunitoSans', label: 'Nunito Sans', family: 'Nunito Sans'),
  UiFont(id: 'Roboto', label: 'Roboto', family: 'Roboto'),
  UiFont(id: 'SourceSans3', label: 'Source Sans 3', family: 'Source Sans 3'),
  UiFont(id: 'WorkSans', label: 'Work Sans', family: 'Work Sans'),
];

/// What the shell falls back to when the chosen family has no glyph.
///
/// The optional faces are Google Fonts' full static files and cover more than
/// the subset default does, but a symbol one of them lacks should still land
/// on the face the rest of the app is drawn in rather than on the engine's own
/// fallback.
const kUiFontFamilyFallback = <String>[ShellVibeTokens.uiFontFamily];

/// Resolves a stored font id (`settings.uiFontFamily`) to a family name a
/// [TextStyle] can use directly.
///
/// Both halves of the shell call this with the same id, which is what keeps
/// Material's widgets and Shad's drawing in one face.
String resolveUiFontFamily(String fontId) => UiFont.of(fontId).family;
