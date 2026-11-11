import 'dart:async';

import '../../terminal/domain/models/terminal_tab_session.dart';
import '../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../domain/services/mcp_session_mirror.dart';

/// Draws an MCP session onto a real read-only terminal tab.
///
/// Same shape as `LiveTemplateRunnerTarget`: a plain adapter holding the
/// notifier, implementing a domain interface, so the MCP session pool keeps
/// talking to [McpSessionMirror] and never learns that tabs exist.
///
/// What lands here is a *rendering* of the session, not its transport: the
/// shell itself lives in the pool, and this only ever writes into the tab's
/// terminal buffer. Nothing the user does in the tab can reach the remote
/// host, which is what makes "read-only" true at the model level rather than
/// only in the widget.
class TerminalTabSessionMirror implements McpSessionMirror {
  final TerminalTabsNotifier notifier;

  const TerminalTabSessionMirror({required this.notifier});

  static const String _reset = '\x1b[0m';
  static const String _dim = '\x1b[2m';
  static const String _bold = '\x1b[1m';
  static const String _red = '\x1b[31m';
  static const String _green = '\x1b[32m';
  static const String _cyan = '\x1b[36m';

  @override
  Future<String?> open({
    required String sessionId,
    required String hostLabel,
    required String cwd,
    required String clientName,
    required String mode,
    required FutureOr<void> Function() onUserClosed,
  }) async {
    final tabId = notifier.openMcpTab(
      mcpSessionId: sessionId,
      title: hostLabel,
      onClose: onUserClosed,
    );
    _write(
      tabId,
      [
        '',
        '$_cyan┌ AI session$_reset $_dim· read-only$_reset',
        '$_dim│ agent$_reset  ${_inert(clientName)}',
        '$_dim│ host$_reset   ${_inert(hostLabel)} $_dim($mode)$_reset',
        '$_dim│ cwd$_reset    ${_inert(cwd)}',
        '$_dim└ closing this tab ends the session$_reset',
        '',
      ].join('\n'),
    );
    return tabId;
  }

  @override
  void writeCommand(
    String surfaceId, {
    required String command,
    required String cwd,
  }) {
    _write(
      surfaceId,
      '$_dim${_inert(cwd)}$_reset\n'
      '$_cyan❯$_reset $_bold${_inert(command)}$_reset',
    );
  }

  @override
  void writeResult(
    String surfaceId, {
    required String stdout,
    required String stderr,
    required int exitCode,
    required int durationMs,
  }) {
    final buffer = StringBuffer();
    if (stdout.isNotEmpty) buffer.write(_inert(stdout));
    if (stderr.isNotEmpty) buffer.write('$_red${_inert(stderr)}$_reset');
    final exitColour = exitCode == 0 ? _green : _red;
    buffer.write(
      '$exitColour exit $exitCode$_reset $_dim· ${durationMs}ms$_reset\n',
    );
    _write(surfaceId, buffer.toString());
  }

  @override
  void writeNotice(String surfaceId, String message) {
    _write(surfaceId, '$_dim— ${_inert(message)}$_reset');
  }

  // C0 controls other than tab and line feed (keeping CRLF intact), DEL and
  // C1 controls.
  static final RegExp _controlChars = RegExp(
    '[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F-\\x9F]|\\r(?!\\n)',
  );

  /// [text] from the agent or the remote host with every control character
  /// shown as `⟨U+XXXX⟩` instead of interpreted, so neither can clear the
  /// tab's scrollback (`\x1b[3J`) or rewrite a line already shown in it —
  /// the tab is the user's record of what the agent did.
  static String _inert(String text) => text.replaceAllMapped(
    _controlChars,
    (m) =>
        '⟨U+${m[0]!.codeUnitAt(0).toRadixString(16).toUpperCase().padLeft(4, '0')}⟩',
  );

  @override
  Future<void> close(String surfaceId, {String? reason}) =>
      notifier.closeMcpTab(surfaceId);

  /// Writes one chunk, translating bare newlines into CRLF.
  ///
  /// The output arrives from a PTY-less channel, so it carries `\n` where a
  /// terminal expects `\r\n`; without this every line would start where the
  /// previous one ended and the whole transcript would walk off to the right.
  void _write(String surfaceId, String text) {
    final tab = _tab(surfaceId);
    if (tab == null) return;
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
    tab.terminal.write('$normalized\r\n');
  }

  TerminalTabSession? _tab(String surfaceId) => notifier.tabById(surfaceId);
}
