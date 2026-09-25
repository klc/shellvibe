import '../models/terminal_tab_session.dart';

/// Tree math over a tab strip's split panes: root lookup, focus-on-close,
/// reordering, swapping and docking.
///
/// Every method here is a pure computation over the `tabs` list it is given
/// (the panes themselves are mutable model objects and are still mutated in
/// place, exactly as the notifier did before this was extracted) — nothing
/// here reads Riverpod state or writes it back. `TerminalTabsNotifier` calls
/// these from its own methods of the same name and assigns the result to
/// `state` itself, so a caller stepping through the notifier's public API
/// sees no difference from before the split.
class TerminalPaneLayout {
  /// Looks a pane up in an arbitrary list, which the close paths need on a
  /// pre-close snapshot rather than on live state.
  TerminalTabSession? findInList(List<TerminalTabSession> tabs, String id) {
    for (final tab in tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  /// Walks [tabs] up the split tree and returns the id of [tab]'s root pane —
  /// the tab it is displayed in. The loop is bounded by the list length so a
  /// corrupted parent link cannot spin forever.
  String rootIdOf(TerminalTabSession tab, List<TerminalTabSession> tabs) {
    var current = tab;
    for (var hops = 0; hops < tabs.length; hops++) {
      final parentId = current.splitParentId;
      if (parentId == null) return current.id;
      final parent = findInList(tabs, parentId);
      if (parent == null) return current.id;
      current = parent;
    }
    return current.id;
  }

  /// Picks the pane that takes focus once [closedTab] and its subtree are
  /// gone, or null when nothing survives to focus.
  ///
  /// Focus must not leave the tab the user was working in: closing one pane of
  /// a split hands focus to another pane of the *same* root tab, and only a tab
  /// that disappears entirely moves focus to a neighbouring tab. Both searches
  /// run in root order rather than by flat index into [oldTabs], where split
  /// panes are appended after every other tab — indexing there lands on an
  /// unrelated tab's pane and silently switches tabs under the user.
  ///
  /// [oldTabs] is the tab list from *before* the close (the notifier's
  /// `state.tabs` at the moment it decided to close something); [remainingTabs]
  /// is what is left afterwards.
  String? focusAfterClose({
    required TerminalTabSession closedTab,
    required List<TerminalTabSession> oldTabs,
    required List<TerminalTabSession> remainingTabs,
  }) {
    if (remainingTabs.isEmpty) return null;

    final rootId = rootIdOf(closedTab, oldTabs);

    // The closed pane's tab survives: stay inside it. The nearest surviving
    // ancestor is the pane that grows into the freed space, so it gets focus;
    // failing that, any surviving pane of the tab beats leaving the tab.
    final survivorsInTab = remainingTabs
        .where((t) => rootIdOf(t, oldTabs) == rootId)
        .toList();
    if (survivorsInTab.isNotEmpty) {
      final survivingIds = survivorsInTab.map((t) => t.id).toSet();
      var ancestorId = closedTab.splitParentId;
      for (var hops = 0; hops < oldTabs.length && ancestorId != null; hops++) {
        if (survivingIds.contains(ancestorId)) return ancestorId;
        ancestorId = findInList(oldTabs, ancestorId)?.splitParentId;
      }
      return survivorsInTab.first.id;
    }

    // The whole tab went away: fall back to the neighbouring tab, counted
    // among root panes only.
    final oldRootIds = oldTabs
        .where((t) => t.splitParentId == null)
        .map((t) => t.id)
        .toList();
    final remainingRoots = remainingTabs
        .where((t) => t.splitParentId == null)
        .toList();
    if (remainingRoots.isEmpty) return remainingTabs.first.id;

    final closedRootIndex = oldRootIds.indexOf(rootId);
    final newIndex =
        closedRootIndex < 0 || closedRootIndex >= remainingRoots.length
        ? remainingRoots.length - 1
        : closedRootIndex;
    return remainingRoots[newIndex].id;
  }

  /// Promotes the heir of [pane]'s [children] into its slot, returning the
  /// rebuilt tab list. Mirrors `TerminalTabsNotifier.closePane`'s non-leaf
  /// path (called only when [children] is non-empty; a leaf pane is a plain
  /// tab close and never reaches here).
  ///
  /// The last child (the pane laid out directly against [pane], see the split
  /// fold in the tab view) becomes the heir and takes [pane]'s parent,
  /// direction and ratio; the earlier children hang off the heir, which
  /// preserves both their relative nesting and their on-screen order.
  List<TerminalTabSession> promoteHeir(
    List<TerminalTabSession> tabs,
    TerminalTabSession pane,
    List<TerminalTabSession> children,
  ) {
    final heir = children.last;
    heir.splitParentId = pane.splitParentId;
    heir.splitDirection = pane.splitDirection;
    heir.splitRatio = pane.splitRatio;
    for (final child in children) {
      if (identical(child, heir)) continue;
      child.splitParentId = heir.id;
    }

    // The fold that lays panes out reads sibling order off this list, so the
    // heir has to inherit the closed pane's position in it, not keep its own.
    final remainingTabs = <TerminalTabSession>[];
    for (final tab in tabs) {
      if (tab.id == pane.id) {
        remainingTabs.add(heir);
        continue;
      }
      if (identical(tab, heir)) continue;
      remainingTabs.add(tab);
    }
    return remainingTabs;
  }

  /// Moves the root tab [tabId] so it becomes the [toIndex]th root tab of the
  /// strip. Returns the reordered list, or null when there is nothing to do
  /// (the tab is not a known root, or it is already at [toIndex]).
  ///
  /// Only the root sessions trade places. Each one keeps the list slots the
  /// roots occupied, in their new order, and every split pane stays exactly
  /// where it is: the layout fold reads sibling order off this list, and a
  /// pane's siblings are panes of its own tab, so no split can be laid out
  /// differently because its tab moved along the strip.
  List<TerminalTabSession>? reorderRoots(
    List<TerminalTabSession> tabs,
    String tabId,
    int toIndex,
  ) {
    final rootSlots = <int>[];
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i].splitParentId == null) rootSlots.add(i);
    }
    final roots = [for (final slot in rootSlots) tabs[slot]];
    final from = roots.indexWhere((tab) => tab.id == tabId);
    if (from == -1) return null;
    final to = toIndex.clamp(0, roots.length - 1);
    if (from == to) return null;

    roots.insert(to, roots.removeAt(from));
    final reordered = [...tabs];
    for (var i = 0; i < rootSlots.length; i++) {
      reordered[rootSlots[i]] = roots[i];
    }
    return reordered;
  }

  /// Exchanges the positions of panes [paneId] and [otherPaneId] of the same
  /// tab. Returns the updated list, or null when the swap is refused (equal
  /// ids, either pane missing, or the panes belong to different tabs).
  ///
  /// This is a swap of what each slot *shows*, not a rearrangement of the
  /// layout: the split directions, the ratios and the nesting all stay exactly
  /// where they are, and only the two sessions trade places. So the children of
  /// each pane stay with the slot rather than travelling with their parent,
  /// which is why they are re-pointed at the other pane before the two slot
  /// descriptions (parent, direction, ratio) are exchanged.
  ///
  /// Keeping the shape of the tree fixed is also what makes this always safe.
  /// Swapping only the parent links would relabel edges the rest of the tree
  /// still points at, and for an ancestor and a descendant two levels apart
  /// that closes a cycle (`a -> b -> a`) and the layout fold never terminates.
  /// Permuting two positions of an unchanged tree cannot.
  ///
  /// Panes of different tabs are refused: only one tab is on screen, so such a
  /// drop cannot be aimed, and it would move a pane out from under the
  /// selection and focus state of the tab it was in.
  List<TerminalTabSession>? swapPanes(
    List<TerminalTabSession> tabs,
    String paneId,
    String otherPaneId,
  ) {
    if (paneId == otherPaneId) return null;

    final index = tabs.indexWhere((t) => t.id == paneId);
    final otherIndex = tabs.indexWhere((t) => t.id == otherPaneId);
    if (index == -1 || otherIndex == -1) return null;

    final pane = tabs[index];
    final other = tabs[otherIndex];
    if (rootIdOf(pane, tabs) != rootIdOf(other, tabs)) return null;

    for (final tab in tabs) {
      if (tab.id == paneId || tab.id == otherPaneId) continue;
      if (tab.splitParentId == paneId) {
        tab.splitParentId = otherPaneId;
      } else if (tab.splitParentId == otherPaneId) {
        tab.splitParentId = paneId;
      }
    }

    final paneParentId = pane.splitParentId;
    final paneDirection = pane.splitDirection;
    final paneRatio = pane.splitRatio;

    // When one pane is the other's parent, the slot it is moving into hangs off
    // the slot it is vacating — which the other pane now holds.
    pane.splitParentId = other.splitParentId == paneId
        ? otherPaneId
        : other.splitParentId;
    pane.splitDirection = other.splitDirection;
    pane.splitRatio = other.splitRatio;

    other.splitParentId = paneParentId == otherPaneId ? paneId : paneParentId;
    other.splitDirection = paneDirection;
    other.splitRatio = paneRatio;

    // Sibling order is read off this list by the layout fold, so the two panes
    // have to take each other's place here as well. Leaving the order alone
    // would move a pane into a slot and then lay it out on the wrong side of
    // the sibling it shares that slot's container with.
    final reordered = [...tabs];
    reordered[index] = other;
    reordered[otherIndex] = pane;

    return reordered;
  }

  /// Moves [paneId] out of its slot and splits [targetId] with it, along
  /// [edge]. Returns the updated list, or null when [paneId] or [targetId] is
  /// missing, or the two belong to different tabs.
  ///
  /// The pane travels alone. Its own children stay behind and are promoted into
  /// the slot it vacates, exactly as [promoteHeir] promotes them — a pane's
  /// children describe how its rectangle is subdivided, so they belong to the
  /// slot rather than to the pane that happens to sit in it.
  ///
  /// A pane always joins its parent's split on the trailing side (the fold that
  /// lays panes out puts the newest child there), so this always docks
  /// trailing; the caller (`TerminalTabsNotifier.movePaneTo`) follows a leading
  /// dock with a [swapPanes] to exchange the two rectangles' occupants.
  List<TerminalTabSession>? dockPane(
    List<TerminalTabSession> tabs,
    String paneId,
    String targetId,
    PaneDockEdge edge,
  ) {
    final pane = findInList(tabs, paneId);
    final target = findInList(tabs, targetId);
    if (pane == null || target == null) return null;
    if (rootIdOf(pane, tabs) != rootIdOf(target, tabs)) return null;

    var result = [...tabs];
    final children = result.where((t) => t.splitParentId == paneId).toList();

    if (children.isEmpty) {
      result.removeWhere((t) => t.id == paneId);
    } else {
      result = promoteHeir(result, pane, children);
    }

    pane.splitParentId = targetId;
    pane.splitDirection = edge.axis;
    pane.splitRatio = 0.5;
    // Appended last so it is the innermost child of its new parent: it splits
    // the target's own rectangle rather than the target plus everything already
    // split off it.
    result.add(pane);

    return result;
  }
}
