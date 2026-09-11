import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm3/xterm.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../settings/domain/models/app_settings_model.dart';
import '../../../settings/presentation/notifiers/settings_notifier.dart';
import '../../domain/models/terminal_palette_data.dart';
import '../../domain/models/terminal_tab_session.dart';
import '../notifiers/terminal_tabs_notifier.dart';
import '../utils/terminal_font_resolver.dart';
import '../widgets/mobile_extra_keys_bar.dart';
import '../widgets/terminal_search_bar.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  final TerminalTabSession session;
  final bool? showExtraKeys;
  final bool readOnly;

  /// Keeps the terminal viewport dimensions stable while the IME is open and
  /// overlays the extra-key bar above the keyboard instead of laying it out
  /// below the terminal. Used by the phone Device Link screen, whose PTY
  /// dimensions belong to the desktop until the phone explicitly resizes.
  final bool keepTerminalSizeWhenKeyboardOpens;

  const TerminalScreen({
    super.key,
    required this.session,
    this.showExtraKeys,
    this.readOnly = false,
    this.keepTerminalSizeWhenKeyboardOpens = false,
  });

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  late final FocusNode _terminalFocus;

  /// Owned here rather than left to [TerminalView] because the find bar drives
  /// the search highlights through it.
  final _terminalController = TerminalController();

  /// Owned for the same reason: jumping to a match is a scroll.
  final _terminalScroll = ScrollController();

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  bool _searchOpen = false;
  bool _searchCaseSensitive = false;
  List<TerminalSearchMatch> _searchMatches = const [];
  int _searchIndex = -1;

  /// Reaches the terminal view so the extra-key bar can hand the session what
  /// the keyboard is still composing before it sends a key of its own.
  final _terminalViewKey = GlobalKey<TerminalViewState>();

  void _flushTerminalInput() {
    final view = _terminalViewKey.currentState;
    if (view == null) return;
    // Nothing composing still means the platform buffer should go back to the
    // state the view expects, so the next delta is measured against it.
    if (!view.commitComposing()) view.resetEditingState();
  }

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
    _terminalController.dispose();
    _terminalScroll.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- search

  /// ⌘F on macOS, Ctrl+Shift+F elsewhere.
  ///
  /// Plain Ctrl+F is not bound: it is `forward-char` in readline and a page
  /// forward in vi, and a terminal that swallows it is a terminal that has
  /// broken the program running inside it. macOS has ⌘ free for exactly this.
  bool _isFindShortcut(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.keyF) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed) return true;
    return keyboard.isControlPressed && keyboard.isShiftPressed;
  }

  /// Runs before [TerminalView]'s own handling, so the shortcut never reaches
  /// the PTY.
  KeyEventResult _handleTerminalKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_isFindShortcut(event)) return KeyEventResult.ignored;
    _openSearch();
    return KeyEventResult.handled;
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    // A repeat press with the bar already open re-focuses the field and
    // selects what is in it, which is what every other find bar does.
    _searchFocus.requestFocus();
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
    if (_searchController.text.isNotEmpty) _runSearch(_searchController.text);
  }

  void _closeSearch() {
    _terminalController.clearSearchHighlights();
    setState(() {
      _searchOpen = false;
      _searchMatches = const [];
      _searchIndex = -1;
    });
    _terminalFocus.requestFocus();
  }

  void _runSearch(String query) {
    final matches = widget.session.terminal.search(
      query,
      caseSensitive: _searchCaseSensitive,
    );
    setState(() {
      _searchMatches = matches;
      _searchIndex = matches.isEmpty ? -1 : matches.length - 1;
    });
    if (matches.isEmpty) {
      _terminalController.clearSearchHighlights();
      return;
    }
    // The newest hit is the one the eye expects on a terminal: output is
    // appended, so a search for something the last command printed should not
    // start at the top of an hour-old scrollback.
    _terminalController.setSearchHighlights(
      widget.session.terminal.buffer,
      matches.map((m) => m.range).toList(),
      currentIndex: _searchIndex,
    );
    _revealCurrentMatch();
  }

  void _stepSearch(int delta) {
    if (_searchMatches.isEmpty) return;
    final next = (_searchIndex + delta) % _searchMatches.length;
    setState(
      () => _searchIndex = next < 0 ? next + _searchMatches.length : next,
    );
    _terminalController.setCurrentSearchHighlight(_searchIndex);
    _revealCurrentMatch();
  }

  void _toggleSearchCase() {
    setState(() => _searchCaseSensitive = !_searchCaseSensitive);
    if (_searchController.text.isNotEmpty) _runSearch(_searchController.text);
  }

  /// Scrolls the current match into the middle of the viewport.
  ///
  /// The match's line is a buffer index and the viewport is measured in
  /// pixels, so the conversion needs the rendered line height, which only the
  /// mounted view knows. A frame is allowed to pass first: a search run from a
  /// `setState` would otherwise measure the view that is being replaced.
  void _revealCurrentMatch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _searchIndex < 0) return;
      if (!_terminalScroll.hasClients) return;
      final view = _terminalViewKey.currentState;
      if (view == null) return;

      final double lineHeight;
      try {
        lineHeight = view.renderTerminal.lineHeight;
        // `renderTerminal` reports an unmounted viewport by throwing, and
        // there is no predicate to ask first. Nothing is wrong when it does:
        // the next search reveals the match.
        // ignore: avoid_catching_errors
      } on StateError {
        return;
      }
      if (lineHeight <= 0) return;

      final position = _terminalScroll.position;
      final line = _searchMatches[_searchIndex].range.normalized.begin.y;
      final target =
          line * lineHeight - position.viewportDimension / 2 + lineHeight;
      _terminalScroll.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
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
    final theme = TerminalPaletteData.themeOf(settings.terminalPalette);

    final shouldShowExtraKeys =
        widget.showExtraKeys ??
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);

    final tokens = ShellVibeTokens.resolve(context);

    final terminalBody = Column(
      children: [
        // A 3px hairline rather than a full progress bar: the pane already
        // carries a warning-coloured ring while it connects, so this only has
        // to show that something is still moving.
        if (session.isConnecting)
          SizedBox(
            height: 3,
            child: LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: tokens.warning.withValues(alpha: 0.12),
              color: tokens.warning,
            ),
          ),
        // A finished or failed SSH session (one with a host to reconnect to)
        // shows the banner with a Reconnect action. Local panes and idle
        // connecting state are excluded. A remote shell that simply exited is
        // not a failure, so it gets a muted banner rather than the red one.
        if (!session.isConnecting &&
            session.sessionType == TerminalSessionType.ssh &&
            session.host != null &&
            !session.isConnected)
          _SessionBanner(
            session: session,
            cleanExit: _isCleanExit(session),
            message: _bannerMessage(session),
            onReconnect: () => ref
                .read(terminalTabsProvider.notifier)
                .reconnectTab(session.id),
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  // The pane's ring lives on the slab in the session tree; here the
                  // fill is flat and opaque so terminal text is never read through a
                  // gradient.
                  color: theme.background,
                  child: StreamBuilder<void>(
                    stream: session.moshPredictionChanges,
                    builder: (context, _) => TerminalView(
                      session.terminal,
                      key: _terminalViewKey,
                      theme: theme,
                      controller: _terminalController,
                      scrollController: _terminalScroll,
                      onKeyEvent: _handleTerminalKey,
                      // Keeps the grid off the pane's ring on every side. The view
                      // insets inside its own background fill, so the gap reads as
                      // terminal rather than as a seam of the pane behind it, and
                      // the columns and rows are measured against the inset box.
                      padding: const EdgeInsets.all(3),
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
                        AppCursorStyle.underline =>
                          TerminalCursorType.underline,
                        AppCursorStyle.bar => TerminalCursorType.verticalBar,
                      },
                      textStyle: TerminalStyle(
                        fontSize: settings.fontSize,
                        fontFamily: resolveTerminalFontFamily(
                          settings.fontFamily,
                        ),
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
              if (_searchOpen)
                Positioned(
                  top: 8,
                  right: 8,
                  child: TerminalSearchBar(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    matchCount: _searchMatches.length,
                    currentMatch: _searchIndex,
                    caseSensitive: _searchCaseSensitive,
                    onQueryChanged: _runSearch,
                    onNext: () => _stepSearch(1),
                    onPrevious: () => _stepSearch(-1),
                    onToggleCaseSensitive: _toggleSearchCase,
                    onClose: _closeSearch,
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    if (!widget.keepTerminalSizeWhenKeyboardOpens ||
        !shouldShowExtraKeys ||
        widget.readOnly) {
      return Column(
        children: [
          Expanded(child: terminalBody),
          if (shouldShowExtraKeys && !widget.readOnly)
            MobileExtraKeysBar(
              terminal: session.terminal,
              outputChain: session.outputChain,
              onFlushInput: _flushTerminalInput,
            ),
        ],
      );
    }

    // Keyboard-stable layout. The terminal is laid out at the height it has
    // with the keyboard closed, so its row count — and with it the desktop PTY
    // — never moves; the strip the keyboard then covers is clipped away from
    // the *top* instead. The bottom of the viewport, where the prompt and the
    // cursor live, therefore stays visible above the extra-key bar instead of
    // sitting behind the keyboard.
    return LayoutBuilder(
      builder: (context, constraints) {
        final terminalHeight =
            constraints.maxHeight - MobileExtraKeysBar.barHeight;
        // Leave at least a couple of rows of terminal on screen: a tall
        // keyboard on a short pane must not squeeze the viewport to nothing
        // (or to a negative height, which would overflow the column).
        final maxInset = terminalHeight - _minVisibleTerminal;
        final keyboardInset = MediaQuery.viewInsetsOf(
          context,
        ).bottom.clamp(0.0, maxInset > 0 ? maxInset : 0.0);
        return Column(
          children: [
            Expanded(
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.bottomCenter,
                  minHeight: terminalHeight,
                  maxHeight: terminalHeight,
                  child: terminalBody,
                ),
              ),
            ),
            MobileExtraKeysBar(
              terminal: session.terminal,
              outputChain: session.outputChain,
              onFlushInput: _flushTerminalInput,
            ),
            SizedBox(height: keyboardInset),
          ],
        );
      },
    );
  }

  /// Terminal height that stays on screen even under the tallest keyboard.
  static const double _minVisibleTerminal = 48;
}

/// The strip a finished or failed SSH pane shows above its terminal.
///
/// A clean exit is muted; a drop is tinted danger and carries the reconnect
/// action, because those are two different situations and the old shared red
/// banner made them look like one.
class _SessionBanner extends StatelessWidget {
  final TerminalTabSession session;
  final bool cleanExit;
  final String message;
  final VoidCallback onReconnect;

  const _SessionBanner({
    required this.session,
    required this.cleanExit,
    required this.message,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final accent = cleanExit ? tokens.textMuted : tokens.danger;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: cleanExit ? 0.06 : 0.10),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.20)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            cleanExit ? LucideIcons.info : LucideIcons.triangleAlert,
            size: 17,
            color: accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cleanExit ? 'Session ended' : 'Connection lost',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cleanExit
                        ? tokens.textSecondary
                        : tokens.dangerMutedText,
                  ),
                ),
                // The headline already says what happened; the mono line is
                // only for the detail underneath it, so an error-free drop
                // shows one line rather than the same words twice.
                if (session.errorMessage != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: shellvibeMono(
                      context,
                      size: 11,
                      color: cleanExit
                          ? tokens.textSubtle
                          : tokens.dangerMutedBorder,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            key: Key('reconnect_${session.id}'),
            onTap: onReconnect,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: cleanExit ? Colors.transparent : tokens.danger,
                borderRadius: BorderRadius.circular(8),
                border: cleanExit
                    ? Border.all(
                        color: tokens.textPrimary.withValues(alpha: 0.08),
                      )
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.refreshCw,
                    size: 14,
                    color: cleanExit
                        ? tokens.textSecondary
                        : tokens.dangerMutedSurface,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Reconnect',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cleanExit
                          ? tokens.textSecondary
                          : tokens.dangerMutedSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
