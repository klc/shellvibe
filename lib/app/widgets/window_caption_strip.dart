import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/shellvibe_tokens.dart';
import '../window/window_chrome.dart';

/// Where the platform title bar used to be, across the top of the shell.
///
/// It carries no fill of its own, so the night canvas reaches the window's top
/// edge. On macOS the traffic lights float on its left end; on Windows and
/// Linux the app's own minimise, maximise and close sit at its right end. The
/// rest is the window's drag handle, and a double-click on it maximises or
/// restores, which [DragToMoveArea] wires for us.
///
/// Draws nothing where the platform keeps a title bar of its own.
class WindowCaptionStrip extends StatelessWidget {
  const WindowCaptionStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final height = windowChromeTopInset;
    if (height <= 0) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: SizedBox(height: height, width: double.infinity),
            ),
          ),
          if (drawsOwnCaptionButtons) const WindowCaptionButtons(),
        ],
      ),
    );
  }
}

/// Minimise, maximise or restore, and close, for a window whose platform
/// caption is hidden.
///
/// Drawn in the shell's own tokens rather than imitating either platform's
/// glyphs: the strip they sit in is the shell's, and a Windows 11 caption on a
/// KDE desktop would match neither. Close turns the palette's danger colour on
/// hover, the one convention both platforms share.
class WindowCaptionButtons extends StatefulWidget {
  const WindowCaptionButtons({super.key});

  @override
  State<WindowCaptionButtons> createState() => _WindowCaptionButtonsState();
}

class _WindowCaptionButtonsState extends State<WindowCaptionButtons>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _readMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _readMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) setState(() => _maximized = maximized);
    } catch (_) {
      // No window behind the channel (a test, a headless run): keep the
      // maximise glyph, which is right for a window that was never maximised.
    }
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _toggleMaximized() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          key: const Key('window_caption_minimize'),
          icon: LucideIcons.minus,
          tooltip: 'Minimize',
          onPressed: () => windowManager.minimize(),
        ),
        _CaptionButton(
          key: const Key('window_caption_maximize'),
          icon: _maximized ? LucideIcons.copy : LucideIcons.square,
          // The restore glyph reads at the same weight as the square only a
          // size down.
          iconSize: _maximized ? 12 : 13,
          tooltip: _maximized ? 'Restore' : 'Maximize',
          onPressed: _toggleMaximized,
        ),
        _CaptionButton(
          key: const Key('window_caption_close'),
          icon: LucideIcons.x,
          tooltip: 'Close',
          isClose: true,
          // Through closeHostWindow, so a tray that keeps the app running
          // intercepts this the same way it does every other close.
          onPressed: closeHostWindow,
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 14,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double iconSize;
  final bool isClose;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final Color background;
    final Color foreground;
    if (widget.isClose && (_hovered || _pressed)) {
      // The palette's danger, with the canvas as its ink: a pastel red with a
      // dark glyph in the night palettes, a saturated one with a light glyph
      // in the day ones.
      background = _pressed
          ? tokens.danger.withValues(alpha: 0.85)
          : tokens.danger;
      foreground = tokens.canvas;
    } else if (_pressed) {
      background = tokens.textPrimary.withValues(alpha: 0.12);
      foreground = tokens.textPrimary;
    } else if (_hovered) {
      background = tokens.textPrimary.withValues(alpha: 0.07);
      foreground = tokens.textPrimary;
    } else {
      background = Colors.transparent;
      foreground = tokens.textMuted;
    }

    return Semantics(
      button: true,
      label: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: Tooltip(
            message: widget.tooltip,
            waitDuration: const Duration(milliseconds: 600),
            child: Container(
              width: 46,
              height: kCaptionStripHeight,
              color: background,
              alignment: Alignment.center,
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the window be resized from its edges where the platform no longer
/// draws a frame to resize it by ([drawsOwnResizeEdges]); passes [child]
/// through untouched everywhere else.
///
/// The edges go away while the window is maximised or full screen, where there
/// is nothing to resize and the strips would only steal clicks from the rail
/// and the terminal's scrollbar.
class WindowResizeEdges extends StatefulWidget {
  const WindowResizeEdges({super.key, required this.child});

  final Widget child;

  @override
  State<WindowResizeEdges> createState() => _WindowResizeEdgesState();
}

class _WindowResizeEdgesState extends State<WindowResizeEdges>
    with WindowListener {
  bool _filling = false;

  @override
  void initState() {
    super.initState();
    if (!drawsOwnResizeEdges) return;
    windowManager.addListener(this);
    _read();
  }

  @override
  void dispose() {
    if (drawsOwnResizeEdges) windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _read() async {
    try {
      final filling =
          await windowManager.isMaximized() ||
          await windowManager.isFullScreen();
      if (mounted) setState(() => _filling = filling);
    } catch (_) {}
  }

  @override
  void onWindowMaximize() => setState(() => _filling = true);

  @override
  void onWindowUnmaximize() => _read();

  @override
  void onWindowEnterFullScreen() => setState(() => _filling = true);

  @override
  void onWindowLeaveFullScreen() => _read();

  @override
  Widget build(BuildContext context) {
    if (!drawsOwnResizeEdges) return widget.child;
    return DragToResizeArea(
      resizeEdgeSize: 6,
      enableResizeEdges: _filling ? const [] : null,
      child: widget.child,
    );
  }
}
