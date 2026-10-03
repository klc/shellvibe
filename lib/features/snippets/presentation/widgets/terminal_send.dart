import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../domain/models/run_target.dart';

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

/// The hosts of the panes [target] would type into, for the production check:
/// the active pane's, or every selected pane's. Panes with no host (local
/// shells) contribute none.
List<HostModel> terminalTargetHosts(TerminalTabsState tabs, RunTarget target) {
  switch (target) {
    case SelectedPanesRunTarget():
      return [
        for (final tab in tabs.tabs)
          if (tabs.selectedPaneIds.contains(tab.id) && tab.host != null)
            tab.host!,
      ];
    case ActivePaneRunTarget():
      final pane =
          tabs.activeTab ?? (tabs.tabs.isEmpty ? null : tabs.tabs.first);
      return [if (pane?.host != null) pane!.host!];
    case HostRunTarget(:final host):
      return [host];
  }
}
