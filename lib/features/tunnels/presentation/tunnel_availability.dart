import 'dart:ui' show Display, FlutterView;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/shellvibe_tokens.dart';
import '../../../core/utils/platform_capabilities.dart';

/// Whether a port forward is worth offering on a device of this kind.
///
/// iOS suspends an app moments after it leaves the screen and closes its
/// sockets with it. On an iPhone that is the whole point of a tunnel undone:
/// the user starts a forward, switches to the browser that was meant to use it
/// and the listener is gone within about half a minute. An iPad can keep
/// ShellVibe on screen beside the browser (Split View, Stage Manager), so a
/// forward there has a real use. Android is unchanged for now.
///
/// "Phone" is decided the way the shell decides it (see `usesRailLayout`): by
/// the *shortest* side against [compactBreakpoint], so a phone held sideways
/// is still a phone. The side measured is the physical display's, not the
/// window's: an iPad in a third of Split View has a window no wider than an
/// iPhone, and that is exactly when tunnels are wanted.
///
/// Only the entry points are gated on this. Rules already saved stay in the
/// database and keep syncing, so a rule made on an iPad is not lost to an
/// iPhone signed into the same account.
bool tunnelsSupportedOnThisDevice({
  required TargetPlatform platform,
  required Size displaySize,
  double compactBreakpoint = _kDefaultCompactBreakpoint,
}) => !_isIPhone(platform, displaySize, compactBreakpoint);

/// Whether the Tunnels screen should warn that forwards stop with the app.
///
/// True on an iPad only: it is the one device where tunnels are offered *and*
/// die in the background. The hint tells the user how to keep them alive.
bool tunnelsNeedForegroundHint({
  required TargetPlatform platform,
  required Size displaySize,
  double compactBreakpoint = _kDefaultCompactBreakpoint,
}) =>
    platform == TargetPlatform.iOS &&
    !_isIPhone(platform, displaySize, compactBreakpoint);

/// Matches `ShellVibeTokens.breakpointCompact`, the shell's phone/tablet line.
const double _kDefaultCompactBreakpoint = 640;

bool _isIPhone(
  TargetPlatform platform,
  Size displaySize,
  double compactBreakpoint,
) =>
    platform == TargetPlatform.iOS &&
    displaySize.shortestSide < compactBreakpoint;

/// The physical display's size in logical pixels, which does not change when
/// the window does.
///
/// The display of [view] when it reports one. Falls back to [fallback] when it
/// does not (no display attached yet, or a zero size or ratio), which is the
/// window's size: wrong for an iPad in Split View, but never a crash.
Size displaySizeOf(FlutterView? view, {required Size fallback}) {
  final display = view?.display;
  return (display == null ? null : _logicalSize(display)) ?? fallback;
}

/// [displaySizeOf] for the view [context] is drawn in.
Size deviceDisplaySizeOf(BuildContext context) =>
    displaySizeOf(View.maybeOf(context), fallback: MediaQuery.sizeOf(context));

/// The primary display's logical size with no [BuildContext] to ask, for
/// places that run outside the widget tree (the router's redirects). Null when
/// the platform reports no display yet.
Size? primaryDisplaySize() {
  final displays = WidgetsBinding.instance.platformDispatcher.displays;
  return displays.isEmpty ? null : _logicalSize(displays.first);
}

Size? _logicalSize(Display display) {
  final ratio = display.devicePixelRatio;
  final size = display.size;
  if (ratio <= 0 || size.isEmpty) return null;
  return size / ratio;
}

/// [tunnelsSupportedOnThisDevice] for this device, decided outside the widget
/// tree. Offered when the display cannot be read: an unknown device keeps the
/// feature rather than losing it.
bool tunnelsSupportedHere() {
  final display = primaryDisplaySize();
  if (display == null) return true;
  return tunnelsSupportedOnThisDevice(
    platform: runtimeTargetPlatform,
    displaySize: display,
  );
}

/// [tunnelsSupportedOnThisDevice] for the device [context] is drawn on.
bool tunnelsSupportedFor(BuildContext context) => tunnelsSupportedOnThisDevice(
  platform: runtimeTargetPlatform,
  displaySize: deviceDisplaySizeOf(context),
  compactBreakpoint: ShellVibeTokens.resolve(context).breakpointCompact,
);

/// [tunnelsNeedForegroundHint] for the device [context] is drawn on.
bool tunnelsNeedForegroundHintFor(BuildContext context) =>
    tunnelsNeedForegroundHint(
      platform: runtimeTargetPlatform,
      displaySize: deviceDisplaySizeOf(context),
      compactBreakpoint: ShellVibeTokens.resolve(context).breakpointCompact,
    );

/// Whether the iPad foreground hint has been dismissed this run.
///
/// Deliberately not persisted: settings are synced, and "I have read the
/// hint" is a fact about one device, not the account. A hint that comes back
/// on the next launch is cheap; a settings migration for it is not.
class TunnelForegroundHintDismissedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

final tunnelForegroundHintDismissedProvider =
    NotifierProvider<TunnelForegroundHintDismissedNotifier, bool>(
      TunnelForegroundHintDismissedNotifier.new,
    );
