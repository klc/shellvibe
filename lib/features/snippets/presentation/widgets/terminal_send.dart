import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../domain/models/run_target.dart';
import '../../domain/services/run_variables.dart';
import '../../domain/services/snippet_variable_parser.dart';

/// Types [code] into an open terminal and presses Enter, the way the terminal's
/// own snippet picker sends one (focused pane, or every selected pane while
/// broadcasting), except that the command is also submitted.
///
/// Returns false when no pane could take it. The send is fire-and-forget: the
/// app cannot see what the shell did with the text, which is why this is the
/// "unverified" option next to a background run's real exit codes.
bool sendToOpenTerminal(
  TerminalTabsState tabs,
  TerminalTabsNotifier notifier,
  RunTarget target,
  String code,
) {
  switch (target) {
    case SelectedPanesRunTarget():
      if (!tabs.isBroadcasting) return false;
      notifier.sendTextToSelectedPanes(code, submit: true);
      return true;
    case ActivePaneRunTarget():
      final pane =
          tabs.activeTab ?? (tabs.tabs.isEmpty ? null : tabs.tabs.first);
      if (pane == null) return false;
      pane.terminal.paste(code);
      // Typed, not pasted: inside a bracketed paste a newline is text.
      pane.terminal.textInput('\r');
      return true;
    case HostRunTarget():
      return false;
  }
}

/// Fills `${SV:...}` in [code] from the active pane's host, which is the one
/// a typed-in command will most plainly run on (a broadcast uses it for every
/// pane). With no pane host the placeholders are left as written and
/// [FilledCode.unresolved] says so, for the caller to tell the user.
FilledCode fillPaneBuiltins(TerminalTabsState tabs, String code) {
  if (SnippetVariableParser.extractBuiltins(code).isEmpty) {
    return FilledCode(code, unresolved: false);
  }
  final pane = tabs.activeTab ?? (tabs.tabs.isEmpty ? null : tabs.tabs.first);
  final host = pane?.host;
  if (host == null) return FilledCode(code, unresolved: true);
  return FilledCode(
    SnippetVariableParser.substituteBuiltins(code, builtinValuesFor(host)),
    unresolved: false,
  );
}

class FilledCode {
  final String code;
  final bool unresolved;
  const FilledCode(this.code, {required this.unresolved});
}
