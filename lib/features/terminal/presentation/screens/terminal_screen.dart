import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:xterm2/xterm.dart';

import '../../../settings/domain/models/app_settings_model.dart';
import '../../../settings/presentation/notifiers/settings_notifier.dart';
import '../../domain/models/terminal_palette_data.dart';
import '../../domain/models/terminal_tab_session.dart';
import '../notifiers/terminal_tabs_notifier.dart';
import '../utils/terminal_font_resolver.dart';
import '../widgets/mobile_extra_keys_bar.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  final TerminalTabSession session;
  final bool? showExtraKeys;

  const TerminalScreen({
    super.key,
    required this.session,
    this.showExtraKeys,
  });

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {


  late final FocusNode _terminalFocus;

  @override
  void initState() {
    super.initState();
    // The terminal must own the keystrokes as soon as it mounts. `autofocus`
    // alone is not enough: the pane is often mounted while some other widget
    // (the tab bar, a dialog) holds focus, and a reused element never re-fires
    // autofocus when the active tab changes.
    _terminalFocus = FocusNode();
    if (kDebugMode) {
      _terminalFocus.debugLabel = 'terminal_${widget.session.id}';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _terminalFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _terminalFocus.dispose();
    super.dispose();
  }

  /// A modifier click (⌘ on macOS; ⌘ or Ctrl elsewhere) toggles this pane in
  /// the broadcast selection and makes it the active origin; a plain click
  /// routes through [TerminalTabsNotifier.tapPane], which clears the
  /// selection when an unselected pane is clicked.
  ///
  /// Note: `onHyperlinkTap` is not wired anywhere, so ⌘+click on a hyperlink
  /// currently opens nothing. The guard below keeps a link click from being
  /// misinterpreted as a broadcast toggle; if URL opening is added later it
  /// won't fight this selection logic.
  void _handleTapUp(TapUpDetails _, CellOffset offset) {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final broadcastModifier =
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        (!isMac &&
            (pressed.contains(LogicalKeyboardKey.controlLeft) ||
                pressed.contains(LogicalKeyboardKey.controlRight)));
    if (broadcastModifier &&
        widget.session.terminal.hyperlinkIdAt(offset) != 0) {
      return;
    }
    ref
        .read(terminalTabsProvider.notifier)
        .tapPane(widget.session.id, broadcastModifier: broadcastModifier);
  }

  @override
  Widget build(BuildContext context) {
    // When this pane becomes the active one (new tab, split, or a tab switch
    // that reuses this element), hand it the keyboard focus explicitly.
    ref.listen(terminalTabsProvider.select((s) => s.activeTabId), (prev, next) {
      if (next == widget.session.id) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _terminalFocus.requestFocus();
        });
      }
    });
    final session = widget.session;
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.value ?? const AppSettingsModel();
    final isBroadcastSelected = ref.watch(
      terminalTabsProvider.select(
        (s) => s.selectedPaneIds.contains(widget.session.id),
      ),
    );

    final theme = TerminalPaletteData.themeOf(settings.terminalPalette);


    final shouldShowExtraKeys = widget.showExtraKeys ??
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);

    return Column(
      children: [
        if (session.isConnecting)
          LinearProgressIndicator(
            backgroundColor: theme.background,
            color: theme.blue,
          ),
        // A failed or dropped SSH session (one with a host to reconnect to)
        // shows the banner with a Reconnect action. Local panes and idle
        // connecting state are excluded.
        if (!session.isConnecting &&
            session.sessionType == TerminalSessionType.ssh &&
            session.host != null &&
            !session.isConnected)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: ShadTheme.of(context).colorScheme.destructive,
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: ShadTheme.of(context).colorScheme.destructiveForeground,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    session.errorMessage != null
                        ? 'Connection Error: ${session.errorMessage}'
                        : 'Connection lost',
                    style: TextStyle(
                      color: ShadTheme.of(context).colorScheme.destructiveForeground,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ShadButton(
                  key: Key('reconnect_${session.id}'),
                  size: ShadButtonSize.sm,
                  leading: const Icon(Icons.refresh, size: 14),
                  onPressed: () => ref
                      .read(terminalTabsProvider.notifier)
                      .reconnectTab(session.id),
                  child: const Text('Reconnect'),
                ),
              ],
            ),
          ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: theme.background,
              border: Border.all(
                color: isBroadcastSelected
                    ? ShadTheme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: TerminalView(
              session.terminal,
              theme: theme,
              focusNode: _terminalFocus,
              autofocus: true,
              deleteDetection: shouldShowExtraKeys,
              onTapUp: _handleTapUp,
              cursorType: switch (settings.cursorStyle) {
                AppCursorStyle.block => TerminalCursorType.block,
                AppCursorStyle.underline => TerminalCursorType.underline,
                AppCursorStyle.bar => TerminalCursorType.verticalBar,
              },
              textStyle: TerminalStyle(
                fontSize: settings.fontSize,
                fontFamily: resolveTerminalFontFamily(settings.fontFamily),
                fontFamilyFallback: kTerminalFontFamilyFallback,
                enableLigatures: settings.enableLigatures,
                // Measured against a reference terminal rendering the same
                // output at the same cell width (8.0px advance in both): its
                // rows sit on an 18px pitch, xterm2's 1.2 default gives ~16px
                // and 1.0 gives 13px, which reads as squat because the cells
                // stay as wide as ever. 1.4 lands on the same 18px pitch.
                height: 1.4,
                // Reference terminals keep bold text in its declared color.
                // xterm2 defaults to remapping colors 0-7 onto 8-15 for bold
                // runs, which silently recolors most shell prompts.
                drawBoldTextWithBrightColors: false,
              ),
            ),
          ),
        ),
        if (shouldShowExtraKeys)
          MobileExtraKeysBar(
            terminal: session.terminal,
          ),
      ],
    );
  }
}
