import 'package:flutter/material.dart';

import '../theme/shellvibe_tokens.dart';
import 'shellvibe_ui.dart';
import 'window_caption_strip.dart';

/// The shell chrome a route gets when it is pushed *over* the navigation shell
/// rather than living inside it.
///
/// [AppNavigationShell] owes the window two things before it may draw: the
/// caption strip the window controls live in, and the panel gap that keeps the
/// slabs off the window edge. A route outside the shell — file transfer, the
/// Device Link flow — has neither, so its own header starts at the very top
/// left of the window and the window controls either land on top of it or are
/// missing altogether. This wrapper hands such a route the same chrome the shell draws, so the
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
                  // The same strip as the shell's, controls and drag handle
                  // included.
                  const WindowCaptionStrip(),
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
