/// Which of the tray icon's variants is on show.
///
/// A state enum, not the numbers it is derived from: a tunnel's transfer speed
/// ticks every second and the icon must not be handed to the OS on every tick,
/// so the tray compares this value and touches the icon only when it changes.
enum TrayIconState {
  /// Nothing to report.
  normal,

  /// At least one forward is up.
  tunnelActive,

  /// Something failed while nobody was looking (a forward stopped with an
  /// error, a session dropped), and the window has not been shown since.
  error,
}

/// The icon state for what is running and whether something failed unseen.
///
/// An error outranks an active tunnel: it is the one that needs the user, and
/// the tunnel count is in the menu anyway.
TrayIconState deriveTrayIconState({
  required int activeTunnelCount,
  required bool attention,
}) {
  if (attention) return TrayIconState.error;
  if (activeTunnelCount > 0) return TrayIconState.tunnelActive;
  return TrayIconState.normal;
}

/// The asset for [state] on the platform.
///
/// macOS draws the menu bar item as a template image, which the system tints
/// from its alpha alone, so its variants differ in shape (a dot, a triangle)
/// and never in colour. Windows takes an `.ico` and Linux a `.png`, both with
/// a coloured badge. Cut by `tool/gen_tray_icons.py`.
String trayIconAsset(
  TrayIconState state, {
  required bool isMacOS,
  required bool isWindows,
}) {
  final suffix = switch (state) {
    TrayIconState.normal => '',
    TrayIconState.tunnelActive => '_tunnel',
    TrayIconState.error => '_error',
  };
  if (isMacOS) return 'assets/brand/tray_macos$suffix.png';
  return 'assets/brand/tray$suffix.${isWindows ? 'ico' : 'png'}';
}
