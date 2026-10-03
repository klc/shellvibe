import 'dart:io';
import 'dart:ui' show Color, Size;

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Overrides the host platform in tests without changing Flutter globals.
@visibleForTesting
TargetPlatform? debugWindowChromeOverride;

TargetPlatform? get _host {
  final override = debugWindowChromeOverride;
  if (override != null) return override;
  if (kIsWeb) return null;
  if (Platform.isMacOS) return TargetPlatform.macOS;
  if (Platform.isWindows) return TargetPlatform.windows;
  if (Platform.isLinux) return TargetPlatform.linux;
  return null;
}

/// Whether the platform title bar is gone and the app draws to the window edge.
///
/// Every desktop. On macOS `setTitleBarStyle(hidden)` hides the title and makes
/// the bar transparent, but leaves the traffic lights floating over the Flutter
/// view. On Windows and Linux the same call takes the whole caption, its close,
/// minimise and maximise buttons included, so the app draws those itself: see
/// [drawsOwnCaptionButtons]. The native caption they replace was a second bar
/// stacked over the shell's own chrome, and on KDE the GTK header bar alone is
/// some 46px of nothing but the window title.
bool get usesHiddenTitleBar =>
    _host == TargetPlatform.macOS ||
    _host == TargetPlatform.windows ||
    _host == TargetPlatform.linux;

/// Whether minimise, maximise and close are the app's own buttons, drawn at the
/// right of the caption strip where both platforms put them.
bool get drawsOwnCaptionButtons =>
    _host == TargetPlatform.windows || _host == TargetPlatform.linux;

/// Whether the window's edges have to be made resizable by the app.
///
/// Linux only: a GTK window without its decoration loses the frame the
/// compositor resized it by. A Windows window keeps its sizing border with the
/// caption hidden.
bool get drawsOwnResizeEdges => _host == TargetPlatform.linux;

/// Smallest window the desktop shell is still usable in.
///
/// Width sits just under the rail tier so a narrowed window can still reach the
/// phone layout deliberately; height is what the SFTP pane header, one screen
/// of file list and the status bar need before they start fighting each other.
const Size kMinimumWindowSize = Size(560, 480);

/// Height of the strip the macOS traffic lights are drawn over.
///
/// The standard title bar is 28pt and the buttons are centred in it, so
/// anything drawn above this offset lands underneath them. The rail is only
/// 56px wide and the three buttons need about 70px, which is why the strip
/// spans the shell rather than being an inset on the rail alone.
const double kTrafficLightStripHeight = 28;

/// Height of the caption strip on Windows and Linux: the compact caption
/// Windows 11 apps with their own title bar use, and room for the 32px-high
/// buttons [drawsOwnCaptionButtons] puts in it.
const double kCaptionStripHeight = 32;

/// Top inset the shell owes the window controls before it may draw its own
/// chrome. Zero wherever the platform still draws a title bar of its own.
double get windowChromeTopInset => switch (_host) {
  TargetPlatform.macOS => kTrafficLightStripHeight,
  TargetPlatform.windows || TargetPlatform.linux => kCaptionStripHeight,
  _ => 0,
};

/// Closes the host window without quitting the app.
///
/// The terminal tab strip owns Cmd-W, so the window's own close shortcut moves
/// up to Shift-Cmd-W the way Terminal.app and iTerm do it — left alone it has
/// nowhere to land, and a window with a hidden title bar is then closable only
/// by its traffic light. On macOS the app outlives the window and the dock icon
/// brings it back; elsewhere the last window closing ends the app, which is
/// what those platforms expect — unless the app keeps running in the tray,
/// in which case the close is intercepted and the window only hidden.
Future<void> closeHostWindow() async {
  if (_host == null) return;
  await windowManager.close();
}

/// Set while the window is being held hidden since launch, cleared by the first
/// [showHostWindow].
bool _hiddenAtLaunch = false;

/// Whether the maximise a normal launch does before showing was skipped, and is
/// owed to the first show.
bool _maximizeOnFirstShow = false;

/// Starts with the window hidden, for a launch at login: only the tray icon is
/// up until the user asks for the window.
///
/// Skips the maximise a normal launch does first (maximising a hidden window
/// can show it on Windows) and owes it to the first [showHostWindow], so the
/// window still opens the way every other launch does.
Future<void> hideHostWindowAtLaunch() async {
  if (_host == null) return;
  _hiddenAtLaunch = true;
  _maximizeOnFirstShow = true;
  try {
    await windowManager.hide();
  } catch (e) {
    debugPrint('[WindowChrome Warning] $e');
  }
}

/// Hides the window again if it is still being held hidden since launch.
///
/// The Linux runner shows the window itself when the first frame lands,
/// which is after [hideHostWindowAtLaunch] has run, so the hide has to be
/// repeated once that frame is in. (The Windows runner leaves showing to the
/// Dart side, and skips its own fallback for a `--hidden` launch.) A no-op
/// once the user has shown the window.
Future<void> keepHostWindowHiddenAtLaunch() async {
  if (!_hiddenAtLaunch) return;
  try {
    await windowManager.hide();
  } catch (e) {
    debugPrint('[WindowChrome Warning] $e');
  }
}

/// Brings the host window back: shown if hidden to the tray, restored if
/// minimised, and focused.
Future<void> showHostWindow() async {
  if (_host == null) return;
  try {
    _hiddenAtLaunch = false;
    if (_maximizeOnFirstShow) {
      _maximizeOnFirstShow = false;
      await windowManager.maximize();
    }
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  } catch (e) {
    debugPrint('[WindowChrome Warning] $e');
  }
}

/// Hides the platform title bar; the shell's caption strip takes its place.
///
/// Call once, before the window is shown — the style change is not animated and
/// applying it to a visible window flashes the bar away.
Future<void> applyWindowChrome() async {
  if (!usesHiddenTitleBar) return;
  await windowManager.setTitleBarStyle(
    TitleBarStyle.hidden,
    // macOS keeps its traffic lights; elsewhere the app draws the buttons.
    windowButtonVisibility: !drawsOwnCaptionButtons,
  );
}

/// Re-tints the native window frame to the active theme: [canvas] is the
/// selected palette's canvas at [brightness].
///
/// The Flutter view covers the window, but the frame still shows through
/// during a live resize.
///
/// Called from the widget layer, so it swallows its own failures: a test
/// harness or a headless run has no window behind the method channel, and the
/// frame's tint is never worth taking the app down for.
Future<void> syncWindowChromeToTheme({
  required Color canvas,
  required Brightness brightness,
}) async {
  if (_host == null) return;
  try {
    await windowManager.setBackgroundColor(canvas);
    await windowManager.setBrightness(brightness);
  } catch (e) {
    debugPrint('[WindowChrome Warning] $e');
  }
}
