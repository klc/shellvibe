import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/terminal_tab_session.dart';
import '../notifiers/terminal_tabs_notifier.dart';
import '../screens/terminal_screen.dart';
import 'pane_drop_target.dart';
import 'resizable_split.dart';
import 'terminal_pane_helpers.dart';

/// The pane tree of one tab: a single terminal, or a nest of [ResizableSplit]s
/// around one terminal per split pane.
///
/// [buildPaneMenuEntries] is the tab bar's business, not this tree's — it adds
/// the split, transfer and template rows to a pane's right-click menu — so it
/// is threaded straight through to each [TerminalScreen] rather than built
/// here.
Widget buildTerminalSessionTree(
  BuildContext context,
  WidgetRef ref,
  TerminalTabSession session,
  List<TerminalTabSession> allTabs,
  ShellVibeTokens tokens, {
  required List<String> paneOrder,
  required String? activePaneId,
  required Set<String> selectedPaneIds,
  required List<AdaptiveMenuEntry<VoidCallback>> Function(
    TerminalTabSession session,
  )
  buildPaneMenuEntries,
  bool squareTopLeft = false,
}) {
  final children = allTabs.where((t) => t.splitParentId == session.id).toList();

  Widget buildSinglePane(TerminalTabSession paneSession) {
    // Key by pane id: reusing the element across session switches would leave
    // stale state behind and never re-fire the pane's focus logic.
    final screen = TerminalScreen(
      key: ValueKey(paneSession.id),
      session: paneSession,
      buildPaneMenuEntries: buildPaneMenuEntries,
      // An AI tab is a window onto an agent's session, not a shell the user
      // drives: the keyboard is off here, so a stray keystroke cannot enter a
      // command the agent never asked for and nobody approved.
      readOnly: paneSession.isMcp,
    );
    final isActivePane = paneSession.id == activePaneId;
    final isBroadcastSelected = selectedPaneIds.contains(paneSession.id);
    final baseRingColor = paneSession.errorMessage != null
        ? tokens.danger.withValues(alpha: 0.30)
        : paneSession.isConnecting
        ? tokens.warning.withValues(alpha: 0.28)
        : isBroadcastSelected || isActivePane
        ? tokens.brand.withValues(alpha: 0.28)
        : tokens.textPrimary.withValues(alpha: 0.06);

    // Every pane is its own slab: rounded, ringed in the colour of its state,
    // and opaque inside. A single-pane tab still gets the ring, but only a
    // split tab gets the header — the header is what names the snippet
    // target, and with one pane there is nothing to disambiguate.
    Widget body = screen;
    if (paneOrder.length >= 2) {
      final paneNumber = paneOrder.indexOf(paneSession.id) + 1;
      final paneLabel = isBroadcastSelected
          ? 'PANE $paneNumber · BROADCAST '
                '${_deliverablePaneCount(allTabs, selectedPaneIds)}/'
                '${selectedPaneIds.length}'
          : isActivePane
          ? 'PANE $paneNumber · ACTIVE'
          : 'PANE $paneNumber';
      final paneLabelColor = isBroadcastSelected || isActivePane
          ? tokens.brand
          : tokens.textSubtle;
      // The header doubles as the pane's drag handle: dropping it on another
      // pane swaps the two. The terminal below is never the handle — a drag
      // starting there is a text selection.
      body = Column(
        children: [
          Draggable<String>(
            data: paneSession.id,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _paneDragFeedback(context, tokens, paneSession),
            childWhenDragging: Opacity(
              opacity: 0.4,
              child: _paneHeader(
                context,
                ref,
                tokens,
                paneSession,
                paneLabel: paneLabel,
                paneLabelColor: paneLabelColor,
                isBroadcastSelected: isBroadcastSelected,
              ),
            ),
            child: _paneHeader(
              context,
              ref,
              tokens,
              paneSession,
              paneLabel: paneLabel,
              paneLabelColor: paneLabelColor,
              isBroadcastSelected: isBroadcastSelected,
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    final radius = Radius.circular(tokens.radiusLarge);
    // A corner cannot curve away underneath the tab that is supposed to be
    // growing out of it, so the merged tab squares the one it covers.
    final paneRadius = BorderRadius.only(
      topLeft: squareTopLeft ? Radius.zero : radius,
      topRight: radius,
      bottomLeft: radius,
      bottomRight: radius,
    );
    final paneBox = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.terminalBg,
        borderRadius: paneRadius,
        boxShadow: tokens.shadowPanel,
      ),
      // The ring is painted over the child, not behind it. A clipped child
      // fills the whole rounded box, so a border in the background decoration
      // survives only where the content happens to be inset — along the
      // corner arcs the terminal painted straight over it and the outline
      // broke.
      foregroundDecoration: BoxDecoration(
        borderRadius: paneRadius,
        border: Border.all(color: baseRingColor),
      ),
      child: body,
    );

    // A single-pane tab has no header to drag and nothing to drop on.
    if (paneOrder.length < 2) return paneBox;

    // The whole pane is the drop target, not just its header: aiming at a
    // 34px strip is far harder than aiming at the pane it belongs to.
    return PaneDropTarget(
      acceptedPaneIds: paneOrder.where((id) => id != paneSession.id).toSet(),
      borderRadius: paneRadius,
      tokens: tokens,
      onSwap: (draggedId) => ref
          .read(terminalTabsProvider.notifier)
          .swapPanes(draggedId, paneSession.id),
      onDock: (draggedId, edge) => ref
          .read(terminalTabsProvider.notifier)
          .movePaneTo(draggedId, paneSession.id, edge),
      child: paneBox,
    );
  }

  Widget resultWidget = buildSinglePane(session);

  if (children.isEmpty) {
    return resultWidget;
  }

  // Newest child first, so it ends up innermost: a split subdivides the
  // rectangle of the pane it was taken from, not that pane plus every sibling
  // split off it earlier. Folding in creation order instead would make a
  // second split of the first pane cut across the whole tab.
  for (final child in children.reversed) {
    final childTree = buildTerminalSessionTree(
      context,
      ref,
      child,
      allTabs,
      tokens,
      paneOrder: paneOrder,
      activePaneId: activePaneId,
      selectedPaneIds: selectedPaneIds,
      buildPaneMenuEntries: buildPaneMenuEntries,
    );
    final direction = child.splitDirection ?? Axis.horizontal;
    resultWidget = ResizableSplit(
      axis: direction,
      first: resultWidget,
      second: childTree,
      ratio: child.splitRatio,
      dividerColor: Colors.transparent,
      dividerKey: Key('split_divider_${child.id}'),
      onRatioChanged: (ratio) => ref
          .read(terminalTabsProvider.notifier)
          .setSplitRatio(child.id, ratio),
    );
  }

  return resultWidget;
}

/// Of the selected panes, how many have a live session handler (i.e. can
/// actually receive input). Shown as `BROADCAST X/Y` on a pane's header.
int _deliverablePaneCount(
  List<TerminalTabSession> allTabs,
  Set<String> selectedPaneIds,
) {
  final tabsById = {for (final tab in allTabs) tab.id: tab};
  var count = 0;
  for (final id in selectedPaneIds) {
    if (tabsById[id]?.terminal.onOutput != null) count++;
  }
  return count;
}

/// Title bar of one pane of a split tab. Also its drag handle.
Widget _paneHeader(
  BuildContext context,
  WidgetRef ref,
  ShellVibeTokens tokens,
  TerminalTabSession paneSession, {
  required String paneLabel,
  required Color paneLabelColor,
  required bool isBroadcastSelected,
}) {
  return Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    color: isBroadcastSelected
        ? tokens.brand.withValues(alpha: 0.08)
        : tokens.terminalChrome,
    child: Row(
      children: [
        ShellVibeStatusDot(
          state: paneSession.errorMessage != null
              ? ShellVibeDotState.error
              : paneSession.isConnected
              ? ShellVibeDotState.online
              : ShellVibeDotState.idle,
          size: 6,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  paneSession.title,
                  style: shellvibeMono(
                    context,
                    size: 11,
                    color: tokens.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // The title is the host's label, which says nothing about where
              // it points; the endpoint is what the old status bar was read
              // for.
              if (terminalEndpointLabel(paneSession) case final endpoint?) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    endpoint,
                    key: Key('pane_endpoint_${paneSession.id}'),
                    style: shellvibeMono(
                      context,
                      size: 10,
                      color: tokens.textSubtle,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (moshQuietBadge(context, tokens, paneSession, showText: true)
            case final badge?) ...[
          badge,
          const SizedBox(width: 10),
        ],
        if (paneSession.attachment != null) ...[
          deviceLinkBadge(ref, tokens, paneSession),
          const SizedBox(width: 10),
        ],
        Text(
          paneLabel,
          key: Key('pane_label_${paneSession.id}'),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            color: paneLabelColor,
          ),
        ),
        // Every pane of a split tab closes on its own, the root one included
        // — closing it promotes a split into its place instead of taking the
        // tab down.
        const SizedBox(width: 10),
        Semantics(
          label: 'Close split pane ${paneSession.title}',
          button: true,
          child: InkWell(
            key: Key('close_split_${paneSession.id}'),
            onTap: () => ref
                .read(terminalTabsProvider.notifier)
                .closePane(paneSession.id),
            child: Padding(
              padding: const EdgeInsets.all(2.0),
              child: Icon(LucideIcons.x, size: 13, color: tokens.textSubtle),
            ),
          ),
        ),
      ],
    ),
  );
}

/// What follows the pointer while a pane header is being dragged.
///
/// It rides under the finger rather than keeping the grab offset, so on a
/// phone the chip is not hidden by the hand holding it. The header itself is
/// as wide as its pane, which would be a feedback widget wider than the
/// screen; this is a chip that just names what is being carried.
Widget _paneDragFeedback(
  BuildContext context,
  ShellVibeTokens tokens,
  TerminalTabSession paneSession,
) {
  return Material(
    color: Colors.transparent,
    child: Transform.translate(
      offset: const Offset(-24, -18),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.terminalChrome,
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
          border: Border.all(color: tokens.brand.withValues(alpha: 0.55)),
          boxShadow: tokens.shadowPanel,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.gripVertical, size: 13, color: tokens.brand),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                paneSession.title,
                style: shellvibeMono(
                  context,
                  size: 11,
                  color: tokens.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
