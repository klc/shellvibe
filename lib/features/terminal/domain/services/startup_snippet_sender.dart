import '../../../hosts/domain/models/host_model.dart';
import '../../../snippets/domain/models/runbook_model.dart';
import '../../../snippets/domain/models/runbook_step_model.dart';
import '../../../snippets/domain/models/snippet_model.dart';
import '../../../snippets/domain/services/run_variables.dart';
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

  /// The startup runbook has a step a pane cannot type: an approval gate, or
  /// a snippet that was deleted. Nothing was sent.
  blocked,

  /// The user declined typing the startup runbook into a production host.
  declined,
  sent,
}

/// Types a snippet into a terminal pane the first time its session is live —
/// Termius' "startup command" — or, for a template pane given one, a runbook.
///
/// Pure Dart behind callbacks, so which snippet wins and when it goes out are
/// tested without a terminal. Wired in `TerminalTabsNotifier`.
class StartupSnippetSender {
  final Future<SnippetModel?> Function(String id) loadSnippet;
  final Future<RunbookModel?> Function(String id) loadRunbook;

  /// Asks before [runbook] is typed into a pane on production [host].
  final Future<bool> Function(RunbookModel runbook, HostModel host) confirmProd;

  /// Types [code] into [tab] and presses Enter.
  final void Function(TerminalTabSession tab, String code) send;

  /// Tells the user about a snippet that could not go out unattended.
  final void Function(String message) notify;

  const StartupSnippetSender({
    required this.loadSnippet,
    required this.loadRunbook,
    required this.confirmProd,
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

    // A pane's runbook replaces any startup snippet. One that was deleted
    // falls back to the snippet, as if it had never been set.
    final runbookId = tab.startupRunbookId;
    final runbook = runbookId == null ? null : await loadRunbook(runbookId);
    if (runbook != null) return _sendRunbook(tab, runbook);

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

  /// Types [runbook]'s steps into [tab] as one block, a line per step, the
  /// way a multi-line snippet goes out. The pane's shell runs them, not the
  /// runbook engine: exit codes, expected output, retries and timeouts do not
  /// apply, so a step that must stop the rest says so itself (`cd x && ...`).
  Future<StartupSnippetOutcome> _sendRunbook(
    TerminalTabSession tab,
    RunbookModel runbook,
  ) async {
    final steps = [...runbook.steps]
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
    final lines = <String>[];
    for (final step in steps) {
      switch (step.kind) {
        case StepKind.command:
          lines.add(step.command);
        case StepKind.snippet:
          final id = step.snippetId;
          final snippet = id == null ? null : await loadSnippet(id);
          if (snippet == null) {
            notify(
              'Startup runbook "${runbook.title}" was not typed: a step\'s '
              'snippet was deleted.',
            );
            return StartupSnippetOutcome.blocked;
          }
          lines.add(snippet.code);
        case StepKind.approval:
          notify(
            'Startup runbook "${runbook.title}" was not typed: a pane cannot '
            'wait for its approval step.',
          );
          return StartupSnippetOutcome.blocked;
      }
    }
    if (lines.isEmpty) return StartupSnippetOutcome.none;

    var code = lines.join('\n');
    if (SnippetVariableParser.extractVariables(code).isNotEmpty) {
      notify(
        'Startup runbook "${runbook.title}" needs input; run it from '
        'Runbooks.',
      );
      return StartupSnippetOutcome.needsInput;
    }
    final host = tab.host;
    if (host != null) {
      code = SnippetVariableParser.substituteBuiltins(
        code,
        builtinValuesFor(host),
      );
      if (host.isProd && !await confirmProd(runbook, host)) {
        return StartupSnippetOutcome.declined;
      }
    }
    send(tab, code);
    return StartupSnippetOutcome.sent;
  }
}
