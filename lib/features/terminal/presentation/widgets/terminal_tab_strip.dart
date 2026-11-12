import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../settings/domain/models/app_settings_model.dart';
import '../../../settings/presentation/notifiers/settings_notifier.dart';
import '../../../templates/domain/models/template_model.dart';
import '../../../templates/presentation/widgets/template_picker_sheet.dart';
import '../../domain/models/terminal_palette_data.dart';
import '../../domain/models/terminal_tab_session.dart';
import '../notifiers/terminal_tabs_notifier.dart';
import 'terminal_pane_helpers.dart';

/// Below this bar width the trailing actions collapse into one overflow menu.
///
/// A hair under the compact tier rather than on it: the bar is inset from the
/// module edge, so it goes compact slightly before the module around it does.
const double _kTabBarCompactWidth = 620;

/// A trailing tab-bar action, rendered either as a tab-shaped icon button or
/// as a row in the compact overflow menu.
class _TabBarAction {
  const _TabBarAction({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

/// The session file transfer would run over: the focused pane when it is an
/// SSH session, otherwise the active tab root if that one is SSH.
///
/// Returns null for a local shell (and when no tab is open) so the toolbar
/// never offers a transfer with nowhere to send files.
TerminalTabSession? _sftpTargetPane(
  TerminalTabsState tabsState,
  TerminalTabSession? activeRootTab,
) {
  final focused = tabsState.activeTab;
  if (focused != null &&
      focused.sessionType == TerminalSessionType.ssh &&
      !focused.isMcp) {
    return focused;
  }
  if (activeRootTab != null &&
      activeRootTab.sessionType == TerminalSessionType.ssh &&
      !activeRootTab.isMcp) {
    return activeRootTab;
  }
  return null;
}

/// The strip of open tabs and its trailing action cluster.
///
/// The strip itself is not a surface: the tabs float on the canvas, and the
/// active one is the only thing that reads as raised.
class TerminalTabStrip extends ConsumerWidget {
  final TerminalTabsState tabsState;
  final TerminalTabSession? activeRootTab;

  /// Splits [paneId], asking the user to verify a host key first when one is
  /// unrecognised.
  final HostKeyPromptCallback onPromptHostKey;

  /// Splits the given pane against a host chosen from a picker.
  final void Function(String paneId) onStartSplitWithHost;

  /// Saves every open tab and split pane as a named template.
  final VoidCallback onSaveTemplate;

  /// Reopens a saved layout.
  final Future<void> Function(TemplateModel template) onRunTemplate;

  /// Scans or shows the Device Link QR, depending on the platform.
  final VoidCallback onDeviceLinkAction;

  /// Opens a tab's right-click menu.
  final Future<void> Function(
    TerminalTabSession tab, {
    required int index,
    required int tabCount,
    required Offset position,
  })
  onShowTabMenu;

  /// The "+" menu, anchored to the button that opened it.
  final void Function(BuildContext buttonContext) onShowNewTabMenu;

  const TerminalTabStrip({
    super.key,
    required this.tabsState,
    required this.activeRootTab,
    required this.onPromptHostKey,
    required this.onStartSplitWithHost,
    required this.onSaveTemplate,
    required this.onRunTemplate,
    required this.onDeviceLinkAction,
    required this.onShowTabMenu,
    required this.onShowNewTabMenu,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    final rootTabs = tabsState.tabs
        .where((t) => t.splitParentId == null)
        .toList();

    // Rounded at the top, square where it meets the terminal — the tab is the
    // top of that panel, not a pill parked above it.
    final tabRadius = BorderRadius.vertical(
      top: Radius.circular(tokens.radiusMedium),
    );
    // Same value the focused pane rings itself with, so the tab's outline and
    // the pane's are one unbroken line.
    final activeTabRing = tokens.textPrimary.withValues(alpha: 0.22);
    // What the terminal body really paints — its own scheme, not the app
    // palette's terminalBg — so the active tab has no seam where it meets it.
    final settings =
        ref.watch(settingsProvider).value ?? const AppSettingsModel();
    final terminalBg = TerminalPaletteData.of(
      settings.resolvedTerminalPalette(Theme.of(context).brightness),
    ).theme.background;

    // Every action except "new tab" is collapsible: on a phone six inline
    // IconButtons eat the whole bar and the tab strip is squeezed to a single
    // clipped character.
    final actions = <_TabBarAction>[
      // File transfer for the focused session. A local shell has no remote
      // side, so the button is absent rather than disabled there.
      if (_sftpTargetPane(tabsState, activeRootTab) case final sftpTarget?)
        _TabBarAction(
          buttonKey: const Key('open_sftp_button'),
          icon: LucideIcons.folderSync,
          label: 'File Transfer (SFTP) — ${sftpTarget.title}',
          onPressed: () => openSftpForPane(context, sftpTarget),
        ),
      // Split Pane Action Buttons (Vertical & Horizontal Split). An AI tab is
      // never split.
      if (activeRootTab?.isMcp == false) ...[
        _TabBarAction(
          buttonKey: const Key('split_vertical_button'),
          icon: LucideIcons.columns2,
          label: 'Split Vertically (Side by Side)',
          onPressed: () {
            final targetId = tabsState.activeTabId ?? activeRootTab!.id;
            unawaited(
              ref
                  .read(terminalTabsProvider.notifier)
                  .splitTab(
                    targetId,
                    direction: Axis.horizontal,
                    onHostKeyPrompt: onPromptHostKey,
                  ),
            );
          },
        ),
        _TabBarAction(
          buttonKey: const Key('split_horizontal_button'),
          icon: LucideIcons.rows2,
          label: 'Split Horizontally (Top/Bottom)',
          onPressed: () {
            final targetId = tabsState.activeTabId ?? activeRootTab!.id;
            unawaited(
              ref
                  .read(terminalTabsProvider.notifier)
                  .splitTab(
                    targetId,
                    direction: Axis.vertical,
                    onHostKeyPrompt: onPromptHostKey,
                  ),
            );
          },
        ),
        _TabBarAction(
          buttonKey: const Key('split_with_host_button'),
          icon: LucideIcons.serverCog,
          label: 'Split with Another Host',
          onPressed: () {
            final targetId = tabsState.activeTabId ?? activeRootTab!.id;
            onStartSplitWithHost(targetId);
          },
        ),
      ],
      // Layout templates: save what is open, or reopen a saved layout.
      // Saving needs something to capture; running does not.
      if (tabsState.tabs.isNotEmpty)
        _TabBarAction(
          buttonKey: const Key('save_template_button'),
          icon: LucideIcons.bookmarkPlus,
          label: 'Save Tabs & Panes as Template',
          onPressed: onSaveTemplate,
        ),
      _TabBarAction(
        buttonKey: const Key('run_template_button'),
        icon: LucideIcons.layoutTemplate,
        label: 'Run Template',
        onPressed: () =>
            TemplatePickerSheet.show(context, onSelect: onRunTemplate),
      ),
      _TabBarAction(
        buttonKey: const Key('device_link_action_button'),
        icon: isMobilePlatform ? LucideIcons.scanQrCode : LucideIcons.qrCode,
        label: isMobilePlatform ? 'Scan Device Link QR' : 'Show Device Link QR',
        onPressed: onDeviceLinkAction,
      ),
    ];

    return SizedBox(
      height: kTerminalTabStripHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _kTabBarCompactWidth;
          final notifier = ref.read(terminalTabsProvider.notifier);
          bool isRootTab(String id) => rootTabs.any((t) => t.id == id);
          // A phone's strip only reorders: its tabs are too narrow to aim a
          // merge at, and too narrow to split once merged.
          bool canMerge(String draggedId, TerminalTabSession target) =>
              !compact &&
              !target.isMcp &&
              !(rootTabs.where((t) => t.id == draggedId).firstOrNull?.isMcp ??
                  true);
          void drop(String draggedId, int targetIndex, _TabDropZone zone) {
            if (zone == _TabDropZone.merge) {
              notifier.mergeTab(draggedId, rootTabs[targetIndex].id);
              return;
            }
            final from = rootTabs.indexWhere((t) => t.id == draggedId);
            var to = zone == _TabDropZone.before
                ? targetIndex
                : targetIndex + 1;
            if (from < to) to--;
            notifier.moveTab(draggedId, to);
          }

          return Row(
            children: [
              Expanded(
                // A tab is dragged by the tab itself. Dropped on either side
                // of another tab it moves there; dropped on its middle, it
                // joins that tab as a split. Past the last tab, it goes last.
                child: DragTarget<_TabDrag>(
                  onWillAcceptWithDetails: (details) =>
                      isRootTab(details.data.tabId),
                  onAcceptWithDetails: (details) =>
                      notifier.moveTab(details.data.tabId, rootTabs.length - 1),
                  builder: (context, _, _) => ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    itemCount: rootTabs.length,
                    itemBuilder: (context, index) {
                      final tab = rootTabs[index];
                      final isActive = tab.id == activeRootTab?.id;
                      final panes = panesOfTab(tabsState.tabs, tab);
                      final paneCount = panes.length;
                      // The tab is named after the pane in focus, so moving
                      // between panes renames it to what you are looking at.
                      final label = panes
                          .firstWhere(
                            (p) => p.id == tabsState.activeTabId,
                            orElse: () => tab,
                          )
                          .displayTitle;
                      // A tab holding one pane is that pane, so it grows out
                      // of it. A tab holding several is the frame around all
                      // of them: joined to the first pane it read as that
                      // pane's header, and its close button as that pane's.
                      final joinsPane = isActive && paneCount < 2;
                      // Tab identity is the host name plus a state dot. The old
                      // colour-coded tab edge is gone: the wireframe wants text to
                      // do the distinguishing so eight tabs stay readable.
                      final dotState = tab.errorMessage != null
                          ? ShellVibeDotState.error
                          : tab.isConnecting
                          ? ShellVibeDotState.idle
                          : tab.isConnected
                          ? ShellVibeDotState.online
                          : ShellVibeDotState.offline;

                      final endpoint = terminalEndpointLabel(tab);
                      final tabChip = Semantics(
                        label: 'Tab $label',
                        selected: isActive,
                        button: true,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () => ref
                                .read(terminalTabsProvider.notifier)
                                .setActiveTab(tab.id),
                            onSecondaryTapDown: (details) => unawaited(
                              onShowTabMenu(
                                tab,
                                index: index,
                                tabCount: rootTabs.length,
                                position: details.globalPosition,
                              ),
                            ),
                            borderRadius: tabRadius,
                            child: AnimatedContainer(
                              duration: tokens.motionFast,
                              key: Key('tab_header_${tab.id}'),
                              height: joinsPane
                                  ? kTerminalTabStripHeight
                                  : kTerminalTabStripHeight - 8,
                              margin: joinsPane
                                  ? EdgeInsets.zero
                                  : const EdgeInsets.symmetric(vertical: 4),
                              constraints: BoxConstraints(
                                minWidth: compact ? 110 : 150,
                                maxWidth: 230,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                // Only the active tab is filled. The rest are text
                                // on the canvas, which is what keeps eight open
                                // sessions from reading as a toolbar.
                                //
                                // A single-pane tab is filled in the terminal's
                                // own colour and has no bottom border — so the
                                // tab does not end, it becomes the pane. A tab
                                // of several panes stands on its own instead.
                                color: joinsPane
                                    ? terminalBg
                                    : isActive
                                    ? tokens.selectedFill
                                    : null,
                                borderRadius: joinsPane
                                    ? tabRadius
                                    : BorderRadius.circular(
                                        tokens.radiusMedium,
                                      ),
                                border: joinsPane
                                    ? Border(
                                        top: BorderSide(color: activeTabRing),
                                        left: BorderSide(color: activeTabRing),
                                        right: BorderSide(color: activeTabRing),
                                      )
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ShellVibeStatusDot(state: dotState, size: 7),
                                  const SizedBox(width: 9),
                                  // The badge is what tells the user, at a
                                  // glance across eight tabs, which shell is
                                  // being driven by something other than them.
                                  if (tab.isMcp) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tokens.brand.withValues(
                                          alpha: 0.16,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'AI',
                                        style: TextStyle(
                                          color: tokens.brand,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                  ],
                                  Flexible(
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isActive
                                            ? tokens.textPrimary
                                            : tokens.textMuted,
                                        fontWeight: isActive
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  if (paneCount > 1) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      key: Key('tab_pane_count_${tab.id}'),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tokens.selectedFill,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '$paneCount',
                                        semanticsLabel: '$paneCount panes',
                                        style: shellvibeMono(
                                          context,
                                          size: 11,
                                          color: tokens.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                  // With the status bar gone these are the
                                  // only trace of a quiet link or an attached
                                  // device on a tab that is not on screen.
                                  for (final pane in panesOfTab(
                                    tabsState.tabs,
                                    tab,
                                  )) ...[
                                    if (moshQuietBadge(
                                          context,
                                          tokens,
                                          pane,
                                          showText: false,
                                        )
                                        case final badge?) ...[
                                      const SizedBox(width: 6),
                                      badge,
                                    ],
                                    if (pane.attachment != null) ...[
                                      const SizedBox(width: 6),
                                      deviceLinkBadge(ref, tokens, pane),
                                    ],
                                  ],
                                  const SizedBox(width: 9),
                                  _TabCloseButton(
                                    tab: tab,
                                    paneCount: paneCount,
                                    tokens: tokens,
                                    onClose: () => ref
                                        .read(terminalTabsProvider.notifier)
                                        .closeTab(tab.id),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                      // The tab shows what is running in it; hovering it says
                      // what the tab was opened as, where it points and the
                      // directory it is in.
                      final tooltipLines = [
                        if (label != tab.title) tab.title,
                        ?endpoint,
                        ?tab.workingDirectory,
                      ];
                      final labelledChip = tooltipLines.isEmpty
                          ? tabChip
                          : Tooltip(
                              key: Key('tab_endpoint_${tab.id}'),
                              message: tooltipLines.join('\n'),
                              waitDuration: const Duration(milliseconds: 500),
                              child: tabChip,
                            );
                      final feedback = Material(
                        color: Colors.transparent,
                        child: Opacity(
                          opacity: 0.85,
                          child: Container(
                            height: kTerminalTabStripHeight,
                            constraints: const BoxConstraints(maxWidth: 230),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: tokens.surfaceRaised,
                              borderRadius: tabRadius,
                              border: Border.all(color: activeTabRing),
                            ),
                            child: Text(
                              tab.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                      final dimmed = Opacity(opacity: 0.4, child: labelledChip);
                      // A pointer drags at once, past the tap slop, so a click
                      // still selects. A finger has to hold first: on a phone a
                      // swipe along the strip is how the tabs are scrolled.
                      final draggable = isMobilePlatform
                          ? LongPressDraggable<_TabDrag>(
                              data: _TabDrag(tab.id),
                              dragAnchorStrategy: pointerDragAnchorStrategy,
                              feedback: feedback,
                              childWhenDragging: dimmed,
                              child: labelledChip,
                            )
                          : Draggable<_TabDrag>(
                              data: _TabDrag(tab.id),
                              dragAnchorStrategy: pointerDragAnchorStrategy,
                              feedback: feedback,
                              childWhenDragging: dimmed,
                              child: labelledChip,
                            );
                      return _TabDropTarget(
                        key: ValueKey('tab_item_${tab.id}'),
                        tabId: tab.id,
                        isTab: isRootTab,
                        canMerge: (draggedId) => canMerge(draggedId, tab),
                        onDrop: (draggedId, zone) =>
                            drop(draggedId, index, zone),
                        tokens: tokens,
                        borderRadius: tabRadius,
                        child: draggable,
                      );
                    },
                  ),
                ),
              ),
              if (compact)
                // The same actions, one tap deeper, so the tab strip keeps its
                // width on a phone.
                PopupMenuButton<_TabBarAction>(
                  key: const Key('tab_bar_overflow_button'),
                  icon: Icon(
                    LucideIcons.ellipsisVertical,
                    size: 18,
                    color: tokens.textPrimary,
                  ),
                  tooltip: 'More Actions',
                  onSelected: (action) => action.onPressed(),
                  itemBuilder: (context) => [
                    for (final action in actions)
                      PopupMenuItem<_TabBarAction>(
                        key: action.buttonKey,
                        value: action,
                        child: Row(
                          children: [
                            Icon(action.icon, size: 17),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                action.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                )
              else
                // Quiet icons on the canvas, like the inactive tabs beside
                // them: no frame, so only the active tab reads as a shape.
                Row(
                  children: [
                    for (final action in actions)
                      _TabBarIconButton(
                        buttonKey: action.buttonKey,
                        icon: action.icon,
                        tooltip: action.label,
                        onPressed: action.onPressed,
                      ),
                  ],
                ),
              // Sets "new tab" apart from the actions on the current one.
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: tokens.border,
              ),
              // New Tab Button
              // The Builder is the menu's anchor: on desktop the dropdown
              // opens under this button, so it needs the button's own box
              // rather than the strip's.
              Builder(
                builder: (buttonContext) => _TabBarIconButton(
                  buttonKey: const Key('new_tab_button'),
                  icon: LucideIcons.plus,
                  tooltip: 'New Tab',
                  onPressed: () => onShowNewTabMenu(buttonContext),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _TabDropZone { before, merge, after }

/// What a tab chip carries while it is dragged. Its own type so a pane's drop
/// target never takes a tab, nor a tab's a pane header (see `PaneDrag`).
class _TabDrag {
  final String tabId;
  const _TabDrag(this.tabId);
}

/// One tab as a drop target: its outer quarters reorder, its middle merges.
///
/// Accepts the tab it wraps as well, so dropping a tab back on itself does
/// nothing instead of falling through to the strip's move-to-end target.
class _TabDropTarget extends StatefulWidget {
  final String tabId;
  final bool Function(String id) isTab;
  final bool Function(String draggedId) canMerge;
  final void Function(String draggedId, _TabDropZone zone) onDrop;
  final ShellVibeTokens tokens;
  final BorderRadius borderRadius;
  final Widget child;

  const _TabDropTarget({
    super.key,
    required this.tabId,
    required this.isTab,
    required this.canMerge,
    required this.onDrop,
    required this.tokens,
    required this.borderRadius,
    required this.child,
  });

  @override
  State<_TabDropTarget> createState() => _TabDropTargetState();
}

class _TabDropTargetState extends State<_TabDropTarget> {
  _TabDropZone? _zone;

  /// Where [globalPointer] falls on this tab, or null for the tab itself.
  /// The drag uses the pointer anchor, so a drop's offset is the pointer.
  _TabDropZone? _zoneAt(Offset globalPointer, String draggedId) {
    if (draggedId == widget.tabId) return null;
    final box = context.findRenderObject()! as RenderBox;
    final x = box.globalToLocal(globalPointer).dx / box.size.width;
    if (widget.canMerge(draggedId) && x >= 0.25 && x <= 0.75) {
      return _TabDropZone.merge;
    }
    return x < 0.5 ? _TabDropZone.before : _TabDropZone.after;
  }

  /// Nudges the strip along while the pointer sits near either end of it, so
  /// a tab can reach a slot that is scrolled out of view.
  // ponytail: moves only on pointer motion, a timer if holding still matters.
  void _autoScroll(Offset globalPointer) {
    final scrollable = Scrollable.maybeOf(context);
    final box = scrollable?.context.findRenderObject() as RenderBox?;
    if (scrollable == null || box == null) return;
    final x = box.globalToLocal(globalPointer).dx;
    final position = scrollable.position;
    const edge = 40.0;
    final delta = x < edge ? -12.0 : (x > box.size.width - edge ? 12.0 : 0.0);
    if (delta == 0) return;
    position.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  void _show(_TabDropZone? zone) {
    if (zone != _zone) setState(() => _zone = zone);
  }

  @override
  Widget build(BuildContext context) {
    final brand = widget.tokens.brand;
    return DragTarget<_TabDrag>(
      onWillAcceptWithDetails: (details) => widget.isTab(details.data.tabId),
      onMove: (details) {
        _show(_zoneAt(details.offset, details.data.tabId));
        _autoScroll(details.offset);
      },
      onLeave: (_) => _show(null),
      onAcceptWithDetails: (details) {
        final zone = _zoneAt(details.offset, details.data.tabId);
        _show(null);
        if (zone != null) widget.onDrop(details.data.tabId, zone);
      },
      builder: (context, _, _) => Stack(
        children: [
          widget.child,
          if (_zone == _TabDropZone.merge)
            Positioned.fill(
              right: 8,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const Key('tab_merge_highlight'),
                  decoration: BoxDecoration(
                    color: brand.withValues(alpha: 0.14),
                    borderRadius: widget.borderRadius,
                    border: Border.all(color: brand.withValues(alpha: 0.6)),
                  ),
                ),
              ),
            ),
          if (_zone == _TabDropZone.before || _zone == _TabDropZone.after)
            Positioned(
              top: 6,
              bottom: 6,
              // In the 8px gap the tab leaves on its right, or on its left
              // edge for a drop in front of it.
              left: _zone == _TabDropZone.before ? 0 : null,
              right: _zone == _TabDropZone.after ? 3 : null,
              width: 2,
              child: IgnorePointer(child: ColoredBox(color: brand)),
            ),
        ],
      ),
    );
  }
}

/// A tab's close button.
///
/// Closing a tab closes every pane in it, and a click aimed at the first
/// pane's close button can land here instead. So a tab of several panes asks
/// once: the first click turns the button into "Close all?" — the pane
/// count beside it says how many — the second
/// closes, and the request lapses after a few seconds if it is not confirmed.
/// A single-pane tab closes on the first click, as before.
class _TabCloseButton extends StatefulWidget {
  final TerminalTabSession tab;
  final int paneCount;
  final ShellVibeTokens tokens;
  final VoidCallback onClose;

  const _TabCloseButton({
    required this.tab,
    required this.paneCount,
    required this.tokens,
    required this.onClose,
  });

  @override
  State<_TabCloseButton> createState() => _TabCloseButtonState();
}

class _TabCloseButtonState extends State<_TabCloseButton> {
  static const _confirmWindow = Duration(seconds: 3);

  bool _armed = false;
  Timer? _lapse;

  void _onTap() {
    if (widget.paneCount < 2 || _armed) {
      _lapse?.cancel();
      widget.onClose();
      return;
    }
    setState(() => _armed = true);
    _lapse = Timer(_confirmWindow, () {
      if (mounted) setState(() => _armed = false);
    });
  }

  @override
  void dispose() {
    _lapse?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    return Semantics(
      label: _armed
          ? 'Confirm closing ${widget.paneCount} panes'
          : 'Close tab ${widget.tab.title}',
      button: true,
      child: InkWell(
        key: Key('close_tab_${widget.tab.id}'),
        onTap: _onTap,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        child: _armed
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Close all?',
                  key: Key('close_tab_confirm_${widget.tab.id}'),
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.danger,
                  ),
                ),
              )
            : Icon(LucideIcons.x, size: 14, color: tokens.textSubtle),
      ),
    );
  }
}

/// Height of the tab strip, which is exactly the height of the tallest thing
/// in it — a tab — so it carries no slack above the terminal.
const double kTerminalTabStripHeight = 38;

/// A 32px quiet icon action in the terminal's top strip.
class _TabBarIconButton extends StatelessWidget {
  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _TabBarIconButton({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: buttonKey,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: tokens.textMuted),
        ),
      ),
    );
  }
}
