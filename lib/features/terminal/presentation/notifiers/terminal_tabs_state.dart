import '../../domain/models/terminal_tab_session.dart';

/// State owned by `TerminalTabsNotifier`: the open tabs/panes, which one is
/// active, and which panes are selected for broadcast input.
class TerminalTabsState {
  final List<TerminalTabSession> tabs;
  final String? activeTabId;

  /// Panes picked with ⌘+click. When two or more are selected the terminal
  /// broadcasts keyboard input and snippets to all of them.
  final Set<String> selectedPaneIds;

  const TerminalTabsState({
    this.tabs = const [],
    this.activeTabId,
    this.selectedPaneIds = const {},
  });

  /// True when broadcast input is live (two or more panes selected).
  bool get isBroadcasting => selectedPaneIds.length >= 2;

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
