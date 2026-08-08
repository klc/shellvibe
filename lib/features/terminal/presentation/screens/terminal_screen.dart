import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm3/xterm.dart';

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
  final bool readOnly;

  const TerminalScreen({
    super.key,
    required this.session,
    this.showExtraKeys,
    this.readOnly = false,
  });

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  late final FocusNode _terminalFocus;

  @override
  void initState() {
    super.initState();
    ref.listenManual(settingsProvider, (previous, next) {
      final mode = next.value?.moshPrediction;
      if (mode != null) widget.session.syncMoshPredictionMode(mode);
    }, fireImmediately: true);
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

  /// True when the session ended because the remote shell exited — an
  /// ordinary logout, not a failure.
  bool _isCleanExit(TerminalTabSession session) =>
      session.errorMessage == null &&
      session.disconnectCause == TerminalDisconnectCause.remoteExit;

  String _bannerMessage(TerminalTabSession session) {
    if (session.errorMessage != null) {
      return 'Connection Error: ${session.errorMessage}';
    }
    return switch (session.disconnectCause) {
      TerminalDisconnectCause.remoteExit => 'Session ended',
      _ => 'Connection lost',
    };
  }

  /// A modifier click (⌘ on macOS; ⌘ or Ctrl elsewhere) toggles this pane in
  /// the broadcast selection and makes it the active origin; a plain click
  /// routes through [TerminalTabsNotifier.tapPane], which clears the
  /// selection when an unselected pane is clicked.
  ///
  /// `onHyperlinkTap` (see [_handleHyperlinkTap]) opens OSC 8 hyperlinks and
  /// plain-text URLs on the same modifier click on desktop, and on a plain
  /// tap on touch. The guard below keeps a link click from also being
  /// interpreted as a broadcast toggle.
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
        (widget.session.terminal.hyperlinkIdAt(offset) != 0 ||
            widget.session.terminal.urlAt(offset) != null)) {
      return;
    }
    ref
        .read(terminalTabsProvider.notifier)
        .tapPane(widget.session.id, broadcastModifier: broadcastModifier);
  }

  static final _uriSchemePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:');

  /// Opens a link tapped/clicked in the terminal (OSC 8 hyperlink or a
  /// detected plain-text URL). Restricted to http(s)/mailto — an OSC 8
  /// hyperlink's URI is attacker-controlled program output, so anything
  /// else (e.g. `file://`) is dropped rather than handed to the OS. A bare
  /// `www.` match from the plain-text detector has no scheme, so it is
  /// treated as https.
  Future<void> _handleHyperlinkTap(String uri) async {
    final normalized = _uriSchemePattern.hasMatch(uri) ? uri : 'https://$uri';
    final parsed = Uri.tryParse(normalized);
    if (parsed == null) return;
    const allowedSchemes = {'http', 'https', 'mailto'};
    if (!allowedSchemes.contains(parsed.scheme.toLowerCase())) return;
    if (!await canLaunchUrl(parsed)) return;
    await launchUrl(parsed, mode: LaunchMode.externalApplication);
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

    final shouldShowExtraKeys =
        widget.showExtraKeys ??
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);

    return Column(
      children: [
        if (session.isConnecting)
          LinearProgressIndicator(
            backgroundColor: theme.background,
            color: theme.blue,
          ),
        // A finished or failed SSH session (one with a host to reconnect to)
        // shows the banner with a Reconnect action. Local panes and idle
        // connecting state are excluded. A remote shell that simply exited is
        // not a failure, so it gets a muted banner rather than the red one.
        if (!session.isConnecting &&
            session.sessionType == TerminalSessionType.ssh &&
            session.host != null &&
            !session.isConnected)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: _isCleanExit(session)
                ? ShadTheme.of(context).colorScheme.muted
                : ShadTheme.of(context).colorScheme.destructive,
            child: Row(
              children: [
                Icon(
                  _isCleanExit(session)
                      ? Icons.info_outline
                      : Icons.error_outline,
                  color: _isCleanExit(session)
                      ? ShadTheme.of(context).colorScheme.mutedForeground
                      : ShadTheme.of(context).colorScheme.destructiveForeground,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _bannerMessage(session),
                    style: TextStyle(
                      color: _isCleanExit(session)
                          ? ShadTheme.of(context).colorScheme.mutedForeground
                          : ShadTheme.of(
                              context,
                            ).colorScheme.destructiveForeground,
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
            child: StreamBuilder<void>(
              stream: session.moshPredictionChanges,
              builder: (context, _) => TerminalView(
                session.terminal,
                theme: theme,
                focusNode: _terminalFocus,
                autofocus: true,
                deleteDetection: shouldShowExtraKeys && !widget.readOnly,
                readOnly: widget.readOnly,
                onTapUp: _handleTapUp,
                onHyperlinkTap: _handleHyperlinkTap,
                predictionText: session.isMosh
                    ? session.moshPredictionEngine.visibleText
                    : null,
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
                  // Configurable in Settings; 1.4 lands on the same 18px pitch
                  // reference terminals use at the default 14px font.
                  height: settings.lineHeightFactor,
                  // Configurable in Settings. Most palettes ship distinct bright
                  // variants, so remapping bold runs from 0-7 onto 8-15 is what
                  // the schemes were authored for; palettes whose brights mirror
                  // the base colors (Rosé Pine, Snazzy, One Light) are unaffected.
                  drawBoldTextWithBrightColors:
                      settings.drawBoldTextWithBrightColors,
                ),
              ),
            ),
          ),
        ),
        if (shouldShowExtraKeys && !widget.readOnly)
          MobileExtraKeysBar(
            terminal: session.terminal,
            outputChain: session.outputChain,
          ),
      ],
    );
  }
}
