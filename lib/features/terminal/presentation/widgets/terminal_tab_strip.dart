import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../templates/domain/models/template_model.dart';
import '../../../templates/presentation/widgets/template_picker_sheet.dart';
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
  if (focused != null && focused.sessionType == TerminalSessionType.ssh) {
    return focused;
  }
  if (activeRootTab != null &&
      activeRootTab.sessionType == TerminalSessionType.ssh) {
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
    final activeTabRing = tokens.brand.withValues(alpha: 0.28);

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
      // Split Pane Action Buttons (Vertical & Horizontal Split)
      if (activeRootTab != null) ...[
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
          return Row(
            children: [
              Expanded(
                // Tabs are dragged into a new order. The handles are the tabs
                // themselves rather than the grip Flutter adds on desktop: a
                // tab is already a pill you would reach for, and a grip icon
                // in each one would cost the title its room.
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, _, _) => Material(
                    color: Colors.transparent,
                    child: Opacity(opacity: 0.85, child: child),
                  ),
                  onReorderItem: (from, to) => ref
                      .read(terminalTabsProvider.notifier)
                      .moveTab(rootTabs[from].id, to),
                  itemCount: rootTabs.length,
                  itemBuilder: (context, index) {
                    final tab = rootTabs[index];
                    final isActive = tab.id == activeRootTab?.id;
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
                      label: 'Tab ${tab.title}',
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
                            height: kTerminalTabStripHeight,
                            constraints: BoxConstraints(
                              minWidth: compact ? 110 : 150,
                              maxWidth: 230,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              // Only the active tab is a slab. The rest are text
                              // on the canvas, which is what keeps eight open
                              // sessions from reading as a toolbar.
                              //
                              // It lifts at the top and settles into the
                              // terminal's own colour at the bottom, where it
                              // has no border at all — so the tab does not end,
                              // it becomes the pane.
                              gradient: isActive
                                  ? LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        tokens.surfaceRaised,
                                        tokens.terminalBg,
                                      ],
                                    )
                                  : null,
                              borderRadius: tabRadius,
                              border: isActive
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
                                    tab.title,
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
                                Semantics(
                                  label: 'Close tab ${tab.title}',
                                  button: true,
                                  child: InkWell(
                                    key: Key('close_tab_${tab.id}'),
                                    onTap: () => ref
                                        .read(terminalTabsProvider.notifier)
                                        .closeTab(tab.id),
                                    child: Icon(
                                      LucideIcons.x,
                                      size: 14,
                                      color: tokens.textSubtle,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                    // The tab names the host by its label; hovering it says
                    // where that label points, which the status bar used to.
                    final labelledChip = endpoint == null
                        ? tabChip
                        : Tooltip(
                            key: Key('tab_endpoint_${tab.id}'),
                            message: endpoint,
                            waitDuration: const Duration(milliseconds: 500),
                            child: tabChip,
                          );
                    // A pointer drags at once, past the tap slop, so a click
                    // still selects. A finger has to hold first: on a phone a
                    // swipe along the strip is how the tabs are scrolled.
                    return KeyedSubtree(
                      key: ValueKey('tab_item_${tab.id}'),
                      child: isMobilePlatform
                          ? ReorderableDelayedDragStartListener(
                              index: index,
                              child: labelledChip,
                            )
                          : ReorderableDragStartListener(
                              index: index,
                              child: labelledChip,
                            ),
                    );
                  },
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
                // Grouped into one hairline cluster: seven loose icon buttons
                // read as a second tab strip, which is exactly the noise
                // Nocturne takes out of the top of the screen.
                //
                // Shaped like a tab, not a pill: rounded at the top, square
                // and unbordered at the bottom, where the pane's own top
                // hairline closes it. The cluster sits on the terminal the
                // same way the active tab does.
                Container(
                  height: kTerminalTabStripHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: tabRadius,
                    border: Border(
                      top: BorderSide(color: tokens.border),
                      left: BorderSide(color: tokens.border),
                      right: BorderSide(color: tokens.border),
                    ),
                  ),
                  child: Row(
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
                ),
              const SizedBox(width: 8),
              // New Tab Button
              // The Builder is the menu's anchor: on desktop the dropdown
              // opens under this button, so it needs the button's own box
              // rather than the strip's.
              Builder(
                builder: (buttonContext) => _TabBarIconButton(
                  buttonKey: const Key('new_tab_button'),
                  icon: LucideIcons.plus,
                  tooltip: 'New Tab',
                  boxed: true,
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

/// Height of the tab strip, which is exactly the height of the tallest thing
/// in it — a tab, and the grouped action pill — so it carries no slack above
/// the terminal.
const double kTerminalTabStripHeight = 38;

/// A 32px quiet icon action in the terminal's top strip.
///
/// [boxed] gives it its own hairline, shaped like a tab — rounded on top,
/// square and open at the bottom where the pane's hairline closes it — for the
/// one action that sits outside the grouped cluster.
class _TabBarIconButton extends StatelessWidget {
  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final bool boxed;
  final VoidCallback onPressed;

  const _TabBarIconButton({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.boxed = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final boxedRadius = BorderRadius.vertical(
      top: Radius.circular(tokens.radiusMedium),
    );
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: buttonKey,
        onTap: onPressed,
        borderRadius: boxed ? boxedRadius : BorderRadius.circular(8),
        child: Container(
          width: boxed ? 34 : 32,
          height: boxed ? kTerminalTabStripHeight : 32,
          alignment: Alignment.center,
          decoration: boxed
              ? BoxDecoration(
                  borderRadius: boxedRadius,
                  border: Border(
                    top: BorderSide(color: tokens.border),
                    left: BorderSide(color: tokens.border),
                    right: BorderSide(color: tokens.border),
                  ),
                )
              : null,
          child: Icon(icon, size: boxed ? 17 : 16, color: tokens.textMuted),
        ),
      ),
    );
  }
}
