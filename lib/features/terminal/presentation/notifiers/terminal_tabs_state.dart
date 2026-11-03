import '../../domain/models/terminal_tab_session.dart';
import '../../domain/services/terminal_pane_layout.dart';

/// State owned by `TerminalTabsNotifier`: the open tabs/panes, which one is
/// active, and which panes are selected for broadcast input.
class TerminalTabsState {
  final List<TerminalTabSession> tabs;
  final String? activeTabId;

  /// Panes picked with ⌘+click, across every tab. Each tab broadcasts on its
  /// own: when two or more panes of one tab are selected, input typed in that
  /// tab reaches all of them and nothing outside it.
  final Set<String> selectedPaneIds;

  const TerminalTabsState({
    this.tabs = const [],
    this.activeTabId,
    this.selectedPaneIds = const {},
  });

  /// True when broadcast input is live in the active tab (two or more of its
  /// panes selected).
  bool get isBroadcasting => activeSelection.length >= 2;

  /// The selected panes of the active tab.
  Set<String> get activeSelection => selectionInTabOf(activeTabId);

  /// The selected panes of the tab [paneId] is displayed in.
  Set<String> selectionInTabOf(String? paneId) {
    final byId = {for (final tab in tabs) tab.id: tab};
    final pane = byId[paneId];
    if (pane == null) return const {};
    final rootId = rootOfPane(tabs, pane).id;
    return {
      for (final id in selectedPaneIds)
        if (byId[id] case final tab? when rootOfPane(tabs, tab).id == rootId)
          id,
    };
  }

  TerminalTabSession? get activeTab {
    if (activeTabId == null) return null;
    try {
      return tabs.firstWhere((t) => t.id == activeTabId);
    } catch (_) {
      return null;
    }
  }

  TerminalTabsState copyWith({
    List<TerminalTabSession>? tabs,
    String? activeTabId,
    bool clearActiveTabId = false,
    Set<String>? selectedPaneIds,
  }) {
    return TerminalTabsState(
      tabs: tabs ?? this.tabs,
      activeTabId: clearActiveTabId ? null : (activeTabId ?? this.activeTabId),
      selectedPaneIds: selectedPaneIds ?? this.selectedPaneIds,
    );
  }
}
