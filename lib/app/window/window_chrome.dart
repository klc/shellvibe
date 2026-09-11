import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/shellvibe_tokens.dart';

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
/// macOS only. `setTitleBarStyle(hidden)` there hides the title and makes the
/// bar transparent, but leaves the traffic lights floating over the Flutter
/// view, so the window keeps its close, minimise and zoom controls. The same
/// call on Windows and Linux takes the whole caption with it — those three
/// buttons included — and a window with no way to be closed is worse than a
/// window whose bar does not match the theme. Both keep their native bar and
/// settle for [syncWindowChromeToTheme] tinting the frame instead.
bool get usesHiddenTitleBar => _host == TargetPlatform.macOS;

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

/// Top inset the shell owes the window controls before it may draw its own
/// chrome. Zero wherever the platform still draws a title bar of its own.
double get windowChromeTopInset =>
    usesHiddenTitleBar ? kTrafficLightStripHeight : 0;

/// Closes the host window without quitting the app.
///
/// The terminal tab strip owns Cmd-W, so the window's own close shortcut moves
/// up to Shift-Cmd-W the way Terminal.app and iTerm do it — left alone it has
/// nowhere to land, and a window with a hidden title bar is then closable only
/// by its traffic light. On macOS the app outlives the window and the dock icon
/// brings it back; elsewhere the last window closing ends the app, which is
/// what those platforms expect.
Future<void> closeHostWindow() async {
  if (_host == null) return;
  await windowManager.close();
}

/// Hides the platform title bar where doing so leaves the window controllable.
///
/// Call once, before the window is shown — the style change is not animated and
/// applying it to a visible window flashes the bar away.
Future<void> applyWindowChrome() async {
  if (!usesHiddenTitleBar) return;
  await windowManager.setTitleBarStyle(
    TitleBarStyle.hidden,
    windowButtonVisibility: true,
  );
}

/// Re-tints the native window frame to the active theme.
///
/// On macOS the Flutter view covers the window, but the frame still shows
/// through during a live resize; on Windows and Linux, which keep their
/// caption, this is the whole of what the platform lets us theme.
///
/// Called from the widget layer, so it swallows its own failures: a test
/// harness or a headless run has no window behind the method channel, and the
/// frame's tint is never worth taking the app down for.
Future<void> syncWindowChromeToTheme(Brightness brightness) async {
  if (_host == null) return;
  final tokens = brightness == Brightness.dark
      ? ShellVibeTokens.dark
      : ShellVibeTokens.light;
  try {
    await windowManager.setBackgroundColor(tokens.canvas);
    await windowManager.setBrightness(brightness);
  } catch (e) {
    debugPrint('[WindowChrome Warning] $e');
  }
}
