import '../../../snippets/domain/models/snippet_model.dart';
import '../../../snippets/domain/services/snippet_variable_parser.dart';
import '../models/terminal_tab_session.dart';

/// What happened to a tab's startup snippet.
enum StartupSnippetOutcome {
  /// Already handled for this tab (a reconnect, or a second live event).
  alreadyHandled,

  /// No snippet applies, or the one named no longer exists.
  none,

  /// The snippet wants `${INPUT:...}` values; nothing was sent.
  needsInput,
  sent,
}

/// Types a snippet into a terminal pane the first time its session is live —
/// Termius' "startup command".
///
/// Pure Dart behind callbacks, so which snippet wins and when it goes out are
/// tested without a terminal. Wired in `TerminalTabsNotifier`.
class StartupSnippetSender {
  final Future<SnippetModel?> Function(String id) loadSnippet;

  /// Types [code] into [tab] and presses Enter.
  final void Function(TerminalTabSession tab, String code) send;

  /// Tells the user about a snippet that could not go out unattended.
  final void Function(String message) notify;

  const StartupSnippetSender({
    required this.loadSnippet,
    required this.send,
    required this.notify,
  });

  /// The snippet that applies to [tab]: the pane's own (a template pane's
  /// override) before its host's default, or null.
  static String? effectiveSnippetId(TerminalTabSession tab) =>
      tab.startupSnippetOverrideId ?? tab.host?.startupSnippetId;

  /// Called whenever [tab]'s session comes up. Only the first call for a tab
  /// does anything: a reconnect of the same tab — after a dropped connection,
  /// or the user pressing Reconnect — must not type the snippet into a shell
  /// that already holds the user's work. A tab that failed to connect has not
  /// had its first live moment yet, so its eventual success still counts.
  ///
  /// A snippet with `${INPUT:...}` variables is not sent: this runs in the
  /// background of a connection with nobody to ask, and sending it with blanks
  /// would run something nobody wrote. The user is told, and runs it from the
  /// snippet picker instead.
  Future<StartupSnippetOutcome> onSessionLive(TerminalTabSession tab) async {
    if (tab.startupSnippetHandled) return StartupSnippetOutcome.alreadyHandled;
    tab.startupSnippetHandled = true;

    final id = effectiveSnippetId(tab);
    if (id == null) return StartupSnippetOutcome.none;
    final snippet = await loadSnippet(id);
    if (snippet == null) return StartupSnippetOutcome.none;

    if (SnippetVariableParser.extractVariables(snippet.code).isNotEmpty) {
      notify(
        'Startup snippet "${snippet.title}" needs input; run it from the '
        'snippet picker.',
      );
      return StartupSnippetOutcome.needsInput;
    }
    send(tab, snippet.code);
    return StartupSnippetOutcome.sent;
  }
}
