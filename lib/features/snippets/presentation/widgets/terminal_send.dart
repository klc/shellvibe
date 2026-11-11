import '../../../terminal/domain/models/terminal_tab_session.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../domain/models/run_target.dart';
import '../../domain/services/run_variables.dart';
import '../../domain/services/snippet_variable_parser.dart';

/// Types [code] into an open terminal and presses Enter, the way the terminal's
/// own snippet picker sends one (focused pane, or every selected pane while
/// broadcasting), except that the command is also submitted. `${SV:...}` is
/// filled from the host of each pane that receives it.
///
/// Returns null when no pane could take it, else whether some `${SV:...}` was
/// left as written for a pane with no host, for the caller to tell the user.
/// The send is fire-and-forget: the app cannot see what the shell did with
/// the text, which is why this is the "unverified" option next to a
/// background run's real exit codes.
bool? sendToOpenTerminal(
  TerminalTabsState tabs,
  TerminalTabsNotifier notifier,
  RunTarget target,
  String code,
) {
  switch (target) {
    case SelectedPanesRunTarget():
      if (!tabs.isBroadcasting) return null;
      return broadcastFilled(notifier, code, submit: true);
    case ActivePaneRunTarget():
      final pane =
          tabs.activeTab ?? (tabs.tabs.isEmpty ? null : tabs.tabs.first);
      if (pane == null) return null;
      final filled = fillBuiltinsFor(pane, code);
      pane.terminal.paste(filled.code);
      // Typed, not pasted: inside a bracketed paste a newline is text.
      pane.terminal.textInput('\r');
      return filled.unresolved;
    case HostRunTarget():
      return null;
  }
}

/// Broadcasts [code] to every selected pane, each with `${SV:...}` filled
/// from its own host: `hostnamectl set-hostname ${SV:HOST_LABEL}` sent to
/// five panes names five machines, not one five times. True when some pane
/// had no host to fill from.
bool broadcastFilled(
  TerminalTabsNotifier notifier,
  String code, {
  bool submit = false,
}) {
  var unresolved = false;
  notifier.sendTextToSelectedPanes(
    code,
    submit: submit,
    textFor: (pane) {
      final filled = fillBuiltinsFor(pane, code);
      unresolved |= filled.unresolved;
      return filled.code;
    },
  );
  return unresolved;
}

/// Fills `${SV:...}` in [code] from [pane]'s host, the machine a typed-in
/// command runs on. With no host the placeholders are left as written and
/// [FilledCode.unresolved] says so, for the caller to tell the user.
FilledCode fillBuiltinsFor(TerminalTabSession? pane, String code) {
  if (SnippetVariableParser.extractBuiltins(code).isEmpty) {
    return FilledCode(code, unresolved: false);
  }
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
