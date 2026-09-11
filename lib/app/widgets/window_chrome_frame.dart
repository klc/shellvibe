import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/shellvibe_tokens.dart';
import '../window/window_chrome.dart';
import 'shellvibe_ui.dart';

/// The shell chrome a route gets when it is pushed *over* the navigation shell
/// rather than living inside it.
///
/// [AppNavigationShell] owes the window two things before it may draw: the
/// strip the macOS traffic lights float on, and the panel gap that keeps the
/// slabs off the window edge. A route outside the shell — file transfer, the
/// Device Link flow — has neither, so its own header starts at the very top
/// left of the window and the close, minimise and zoom buttons land on top of
/// it. This wrapper hands such a route the same chrome the shell draws, so the
/// two look like one app and nothing is drawn underneath the window controls.
class WindowChromeFrame extends StatelessWidget {
  final Widget child;

  const WindowChromeFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final isDesktop = usesRailLayout(context);

    return ShellVibeCanvas(
      child: SafeArea(
        // No tab bar underneath a pushed route on a phone, so unlike the shell
        // this one owes the gesture area its inset on every platform.
        child: isDesktop
            ? Column(
                children: [
                  // Carries no fill of its own: the canvas reaches the window's
                  // top edge and the traffic lights float on it. It is the
                  // drag handle too, matching the shell's own strip.
                  if (windowChromeTopInset > 0)
                    DragToMoveArea(
                      child: SizedBox(
                        height: windowChromeTopInset,
                        width: double.infinity,
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(tokens.panelGap),
                      child: child,
                    ),
                  ),
                ],
              )
            : child,
      ),
    );
  }
}
