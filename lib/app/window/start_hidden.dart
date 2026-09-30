/// Command-line argument the login item starts ShellVibe with (Windows and
/// Linux; macOS cannot pass one and reports the launch through the OS, see
/// `MacOsLaunchAtLogin.wasLaunchedAtLogin`).
const String kStartHiddenArgument = '--hidden';

/// Whether the launch should leave the window hidden and show only the tray
/// icon.
///
/// Both halves are needed. A launch at login that shows the window is an app
/// opening over whatever the user is doing the moment they sign in; but a
/// launch that hides the window with no tray icon to bring it back through is
/// an app that is running and cannot be found. So with the tray off the window
/// shows as it would on any launch.
bool shouldStartHidden({
  required bool launchedAtLogin,
  required bool trayEnabled,
}) => launchedAtLogin && trayEnabled;

/// Resolves the start-hidden decision for this launch.
///
/// The settings are read only for a launch that came from the login item:
/// an ordinary launch needs no storage read before its window is up.
///
/// Anything that goes wrong reading the launch reason or the setting shows the
/// window. An error must never produce the invisible app.
Future<bool> resolveStartHidden({
  required List<String> args,
  required bool isMacOS,
  required Future<bool> Function() macOsLaunchedAtLogin,
  required Future<bool> Function() readTrayEnabled,
}) async {
  try {
    final launchedAtLogin = isMacOS
        ? await macOsLaunchedAtLogin()
        : args.contains(kStartHiddenArgument);
    if (!launchedAtLogin) return false;
    return shouldStartHidden(
      launchedAtLogin: true,
      trayEnabled: await readTrayEnabled(),
    );
  } catch (_) {
    return false;
  }
}
