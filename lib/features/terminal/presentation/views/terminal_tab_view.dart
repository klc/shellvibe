import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/network/mosh_session_manager.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../../snippets/domain/models/snippet_model.dart';
import '../../../snippets/domain/services/snippet_variable_parser.dart';
import '../../../snippets/presentation/notifiers/snippets_notifier.dart';
import '../../../snippets/presentation/widgets/variable_input_dialog.dart';
import '../../../templates/domain/models/template_model.dart';
import '../../../templates/presentation/dialogs/save_template_dialog.dart';
import '../../../templates/presentation/notifiers/templates_notifier.dart';
import '../../../templates/presentation/widgets/template_picker_sheet.dart';
import '../../../tunnels/presentation/providers/tunnels_providers.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../domain/models/terminal_tab_session.dart';
import '../dialogs/host_key_prompt_dialog.dart';
import '../notifiers/terminal_tabs_notifier.dart';
import '../screens/terminal_screen.dart';
import '../widgets/pane_drop_target.dart';
import '../widgets/resizable_split.dart';

/// Below this bar width the trailing actions collapse into one overflow menu.
///
/// A hair under the compact tier rather than on it: the bar is inset from the
/// module edge, so it goes compact slightly before the module around it does.
const double _kTabBarCompactWidth = 620;

/// Height of the tab strip, which is exactly the height of the tallest thing
/// in it — a tab, and the grouped action pill — so it carries no slack above
/// the terminal.
const double _kTabBarHeight = 38;

/// How far the strip reaches down over the pane below it.
///
/// One pixel: the width of the pane's own top border, which the active tab has
/// to cover for the tab and the terminal to read as a single outline.
const double _kTabPaneOverlap = 1;

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

class TerminalTabView extends ConsumerStatefulWidget {
  const TerminalTabView({super.key});

  @override
  ConsumerState<TerminalTabView> createState() => _TerminalTabViewState();
}

class _TerminalTabViewState extends ConsumerState<TerminalTabView> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  TerminalTabSession? _resolveRootTab(TerminalTabsState tabsState) {
    final activeTab = tabsState.activeTab;
    if (activeTab == null) return null;
    var current = activeTab;
    while (current.splitParentId != null) {
      final parent = tabsState.tabs.firstWhere(
        (t) => t.id == current.splitParentId,
        orElse: () => current,
      );
      if (parent.id == current.id) break;
      current = parent;
    }
    return current;
  }

  @override
  Widget build(BuildContext context) {
    final tabsState = ref.watch(terminalTabsProvider);
    final activeRootTab = _resolveRootTab(tabsState);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          if (supportsLocalShell) ...{
            const SingleActivator(LogicalKeyboardKey.keyT, meta: true): () {
              ref.read(terminalTabsProvider.notifier).openLocalTab();
            },
            const SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
              ref.read(terminalTabsProvider.notifier).openLocalTab();
            },
          },
          const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () {
            if (activeRootTab != null) {
              ref
                  .read(terminalTabsProvider.notifier)
                  .closeTab(activeRootTab.id);
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
            if (activeRootTab != null) {
              ref
                  .read(terminalTabsProvider.notifier)
                  .closeTab(activeRootTab.id);
            }
          },
        },
        child: Scaffold(
          // The shell already painted the canvas; the terminal contributes the
          // tab strip, the pane slabs and the status strip, nothing behind them.
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              // The tab and its terminal are one shape, not two stacked slabs.
              // A Column can't reorder painting, so the strip is stacked over
              // the pane and the pane starts one pixel under it: the active
              // tab is filled in the terminal's own colour and has no bottom
              // border, so that pixel is where it swallows the pane's top
              // hairline and the two outlines become a single folder tab.
              Expanded(
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        top: _kTabBarHeight - _kTabPaneOverlap,
                      ),
                      child: activeRootTab == null
                          ? ShellVibePanel(
                              gradientExtent: 220,
                              child: _buildEmptyState(context, ref),
                            )
                          : _buildTabBody(
                              context,
                              ref,
                              tabsState,
                              activeRootTab,
                            ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildTabBar(
                        context,
                        ref,
                        tabsState,
                        activeRootTab,
                      ),
                    ),
                  ],
                ),
              ),
              if (activeRootTab != null) ...[
                _SnippetDrawer(onSend: (code) => _sendToPanes(tabsState, code)),
                _buildStatusBar(context, tabsState, activeRootTab),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(
    BuildContext context,
    WidgetRef ref,
    TerminalTabsState tabsState,
    TerminalTabSession? activeRootTab,
  ) {
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
          onPressed: () => _openSftpForPane(sftpTarget),
        ),
      // Split Pane Action Buttons (Vertical & Horizontal Split)
      if (activeRootTab != null) ...[
        _TabBarAction(
          buttonKey: const Key('split_vertical_button'),
          icon: LucideIcons.columns2,
          label: 'Split Vertically (Side by Side)',
          onPressed: () {
            final targetId = tabsState.activeTabId ?? activeRootTab.id;
            unawaited(
              ref
                  .read(terminalTabsProvider.notifier)
                  .splitTab(
                    targetId,
                    direction: Axis.horizontal,
                    onHostKeyPrompt: _promptHostKey,
                  ),
            );
          },
        ),
        _TabBarAction(
          buttonKey: const Key('split_horizontal_button'),
          icon: LucideIcons.rows2,
          label: 'Split Horizontally (Top/Bottom)',
          onPressed: () {
            final targetId = tabsState.activeTabId ?? activeRootTab.id;
            unawaited(
              ref
                  .read(terminalTabsProvider.notifier)
                  .splitTab(
                    targetId,
                    direction: Axis.vertical,
                    onHostKeyPrompt: _promptHostKey,
                  ),
            );
          },
        ),
        _TabBarAction(
          buttonKey: const Key('split_with_host_button'),
          icon: LucideIcons.serverCog,
          label: 'Split with Another Host',
          onPressed: () {
            final targetId = tabsState.activeTabId ?? activeRootTab.id;
            _startSplitWithHost(targetId);
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
          onPressed: _saveCurrentLayoutAsTemplate,
        ),
      _TabBarAction(
        buttonKey: const Key('run_template_button'),
        icon: LucideIcons.layoutTemplate,
        label: 'Run Template',
        onPressed: () =>
            TemplatePickerSheet.show(context, onSelect: _runTemplate),
      ),
      _TabBarAction(
        buttonKey: const Key('device_link_action_button'),
        icon: isMobilePlatform ? LucideIcons.scanQrCode : LucideIcons.qrCode,
        label: isMobilePlatform ? 'Scan Device Link QR' : 'Show Device Link QR',
        onPressed: () {
          if (isMobilePlatform) {
            unawaited(context.push('/device-link/scan'));
          } else {
            unawaited(_openDeviceLinkQr(context, ref));
          }
        },
      ),
    ];

    // The strip itself is not a surface: the tabs float on the canvas, and the
    // active one is the only thing that reads as raised.
    return SizedBox(
      height: _kTabBarHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _kTabBarCompactWidth;
          return Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
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

                    return Semantics(
                      label: 'Tab ${tab.title}',
                      selected: isActive,
                      button: true,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: () => ref
                              .read(terminalTabsProvider.notifier)
                              .setActiveTab(tab.id),
                          borderRadius: tabRadius,
                          child: AnimatedContainer(
                            duration: tokens.motionFast,
                            key: Key('tab_header_${tab.id}'),
                            height: _kTabBarHeight,
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
                  height: _kTabBarHeight,
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
                  onPressed: () => _showNewTabMenu(buttonContext, ref),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabBody(
    BuildContext context,
    WidgetRef ref,
    TerminalTabsState tabsState,
    TerminalTabSession activeRootTab,
  ) {
    final tokens = ShellVibeTokens.resolve(context);
    // Only the first tab starts at the panel's left edge, so only then is the
    // top-left corner the one the merged tab grows out of. On any later tab
    // that corner sits under an inactive tab — text on the canvas, nothing to
    // merge with — and it keeps its curve.
    final rootTabs = tabsState.tabs.where((t) => t.splitParentId == null);
    final activeIsFirstTab =
        rootTabs.isNotEmpty && rootTabs.first.id == activeRootTab.id;
    return _buildSessionTree(
      context,
      ref,
      activeRootTab,
      tabsState.tabs,
      tokens,
      paneOrder: _paneOrder(tabsState, activeRootTab),
      activePaneId: tabsState.activeTabId,
      selectedPaneIds: tabsState.selectedPaneIds,
      squareTopLeft: activeIsFirstTab,
    );
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

  void _openSftpForPane(TerminalTabSession pane) {
    final label = pane.host?.label ?? pane.title;
    GoRouter.of(context).push(
      '/sftp?tab=${Uri.encodeComponent(pane.id)}'
      '&label=${Uri.encodeComponent(label)}',
    );
  }

  /// Depth-first pane ids of the active tab, so pane headers can be numbered
  /// the same way they are laid out.
  List<String> _paneOrder(
    TerminalTabsState tabsState,
    TerminalTabSession root,
  ) {
    final order = <String>[];
    void walk(TerminalTabSession session) {
      order.add(session.id);
      for (final child in tabsState.tabs.where(
        (tab) => tab.splitParentId == session.id,
      )) {
        walk(child);
      }
    }

    walk(root);
    return order;
  }

  /// Sends snippet text to the focused pane, or to every selected pane while
  /// broadcast input is active (two or more panes selected).
  void _sendToPanes(TerminalTabsState tabsState, String code) {
    if (tabsState.isBroadcasting) {
      ref.read(terminalTabsProvider.notifier).sendTextToSelectedPanes(code);
      return;
    }
    final target =
        tabsState.activeTab ??
        (tabsState.tabs.isEmpty ? null : tabsState.tabs.first);
    if (target == null) return;
    target.terminal.paste(code);
  }

  /// Of the selected panes, how many have a live session handler (i.e. can
  /// actually receive input). Shown as `broadcast X/Y` in the status bar.
  int _deliverablePaneCount(TerminalTabsState tabsState) {
    final tabsById = {for (final tab in tabsState.tabs) tab.id: tab};
    var count = 0;
    for (final id in tabsState.selectedPaneIds) {
      if (tabsById[id]?.terminal.onOutput != null) count++;
    }
    return count;
  }

  Widget _buildStatusBar(
    BuildContext context,
    TerminalTabsState tabsState,
    TerminalTabSession activeRootTab,
  ) {
    final pane = tabsState.activeTab ?? activeRootTab;
    final activeTunnels =
        ref.watch(activeTunnelsStreamProvider).value ?? const [];
    final host = pane.host;
    final attachedTabs = tabsState.tabs
        .where((tab) => tab.attachment != null)
        .toList(growable: false);
    final connectionLabel = pane.errorMessage != null
        ? 'error'
        : pane.isConnecting
        ? 'connecting'
        : pane.isConnected
        ? 'connected'
        : 'disconnected';

    return ShellVibeStatusBar(
      segments: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShellVibeStatusDot(
              state: pane.errorMessage != null
                  ? ShellVibeDotState.error
                  : pane.isConnected
                  ? ShellVibeDotState.online
                  : ShellVibeDotState.offline,
            ),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                pane.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Text(connectionLabel),
        if (host != null) Text('${host.hostname}:${host.port}'),
        // Only shown once a Mosh link has gone quiet. Silence is not a
        // disconnect here — the session is alive and will catch up — but the
        // difference between "slow" and "dropped" is invisible without it,
        // and on this protocol the user cannot tell them apart any other way.
        if (pane.moshLinkState?.status == MoshLinkStatus.stale)
          Text(
            'mosh quiet ${pane.moshLinkState!.silence.inSeconds}s',
            style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
          ),
        if (tabsState.selectedPaneIds.length >= 2)
          Text(
            'broadcast '
            '${_deliverablePaneCount(tabsState)}/'
            '${tabsState.selectedPaneIds.length}',
          ),
        Text('${pane.terminal.viewWidth}×${pane.terminal.viewHeight}'),
        Text('tunnels ${activeTunnels.length}'),
        for (final attachedTab in attachedTabs)
          Row(
            key: Key('device_link_attachment_${attachedTab.id}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.link,
                size: 13,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text('Device Link · ${attachedTab.title}'),
              ShellVibeIconButton(
                key: Key('device_link_disconnect_${attachedTab.id}'),
                icon: Icons.link_off,
                tooltip: 'Disconnect Device Link',
                onPressed: () => unawaited(
                  ref
                      .read(terminalTabsProvider.notifier)
                      .disconnectDeviceLink(attachedTab.id),
                ),
              ),
            ],
          ),
      ],
      trailing: Text(
        pane.isMosh
            ? 'UTF-8 · mosh'
            : pane.sessionType == TerminalSessionType.ssh
            ? 'UTF-8 · ssh'
            : 'UTF-8 · local',
      ),
    );
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
            child: Text(
              paneSession.title,
              style: shellvibeMono(
                context,
                size: 11,
                color: tokens.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
          // Every pane of a split tab closes on its own, the root one
          // included — closing it promotes a split into its place
          // instead of taking the tab down.
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

  Widget _buildSessionTree(
    BuildContext context,
    WidgetRef ref,
    TerminalTabSession session,
    List<TerminalTabSession> allTabs,
    ShellVibeTokens tokens, {
    required List<String> paneOrder,
    required String? activePaneId,
    required Set<String> selectedPaneIds,
    bool squareTopLeft = false,
  }) {
    final children = allTabs
        .where((t) => t.splitParentId == session.id)
        .toList();

    Widget buildSinglePane(TerminalTabSession paneSession) {
      // Key by pane id: reusing the element across session switches would
      // leave stale state behind and never re-fire the pane's focus logic.
      final screen = TerminalScreen(
        key: ValueKey(paneSession.id),
        session: paneSession,
        // An AI tab is a window onto an agent's session, not a shell the user
        // drives: the keyboard is off here, so a stray keystroke cannot enter
        // a command the agent never asked for and nobody approved.
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

      // Every pane is its own slab: rounded, ringed in the colour of its
      // state, and opaque inside. A single-pane tab still gets the ring, but
      // only a split tab gets the header — the header is what names the
      // snippet target, and with one pane there is nothing to disambiguate.
      Widget body = screen;
      if (paneOrder.length >= 2) {
        final paneNumber = paneOrder.indexOf(paneSession.id) + 1;
        final paneLabel = isBroadcastSelected
            ? 'PANE $paneNumber · BROADCAST'
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
        // fills the whole rounded box, so a border in the background
        // decoration survives only where the content happens to be inset —
        // along the corner arcs the terminal painted straight over it and the
        // outline broke.
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
      final childTree = _buildSessionTree(
        context,
        ref,
        child,
        allTabs,
        tokens,
        paneOrder: paneOrder,
        activePaneId: activePaneId,
        selectedPaneIds: selectedPaneIds,
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

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    // The empty screen is where a keyboard-first app teaches its keys. Only on
    // a keyboard, though: a phone has no ⌘ to press, and the row is 96px wider
    // than a 375px screen anyway.
    final tokens = ShellVibeTokens.resolve(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final body = _buildEmptyStateBody(context, ref);
        if (constraints.maxWidth < tokens.breakpointCompact) return body;
        return Column(
          children: [
            Expanded(child: body),
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: DefaultTextStyle.merge(
                style: shellvibeMono(
                  context,
                  size: 11,
                  color: ShellVibeTokens.resolve(context).textSubtle,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('⌘T new tab'),
                    SizedBox(width: 22),
                    Text('⌘K command palette'),
                    SizedBox(width: 22),
                    Text('⌘1…7 modules'),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyStateBody(BuildContext context, WidgetRef ref) {
    return ShellVibeEmptyState(
      icon: LucideIcons.squareTerminal,
      title: 'No open sessions',
      description: isMobilePlatform
          ? 'Connect to a saved server, or take over a session from your '
                'desktop.'
          : 'Open a local shell, connect to a saved server, or take over a '
                'session from your phone.',
      actions: [
        if (supportsLocalShell)
          ShellVibeButton(
            buttonKey: const Key('empty_open_local_button'),
            icon: LucideIcons.monitor,
            label: 'Local shell',
            onPressed: () =>
                ref.read(terminalTabsProvider.notifier).openLocalTab(),
          ),
        ShellVibeButton.secondary(
          buttonKey: const Key('empty_select_host_button'),
          icon: LucideIcons.server,
          label: 'Connect to host',
          onPressed: () => _showSelectHostModal(context, ref),
        ),
        ShellVibeButton.secondary(
          buttonKey: const Key('empty_device_link_button'),
          icon: isMobilePlatform ? LucideIcons.scanQrCode : LucideIcons.qrCode,
          label: 'Device Link',
          onPressed: () {
            if (isMobilePlatform) {
              unawaited(context.push('/device-link/scan'));
            } else {
              unawaited(_openDeviceLinkQr(context, ref));
            }
          },
        ),
      ],
    );
  }

  Future<void> _openDeviceLinkQr(BuildContext context, WidgetRef ref) async {
    try {
      final payload = await ref
          .read(terminalTabsProvider.notifier)
          .createDeviceLinkPairingPayload();
      if (!context.mounted) return;
      await context.push('/device-link/pair', extra: payload);
    } catch (error) {
      if (!context.mounted) return;
      ShadToaster.of(context).show(
        ShadToast.destructive(
          description: Text('Device Link server could not start: $error'),
        ),
      );
    }
  }

  /// The "+" menu. Desktop anchors it to the button it came from; a phone
  /// gets the same rows as a sheet.
  Future<void> _showNewTabMenu(BuildContext context, WidgetRef ref) async {
    final action = await showAdaptiveActionMenu<_NewTabAction>(
      context: context,
      actions: [
        if (supportsLocalShell)
          const AdaptiveMenuAction(
            value: _NewTabAction.localShell,
            itemKey: Key('new_tab_menu_local'),
            icon: LucideIcons.monitor,
            label: 'Local Shell',
          ),
        const AdaptiveMenuAction(
          value: _NewTabAction.connectToHost,
          itemKey: Key('new_tab_menu_host'),
          icon: LucideIcons.server,
          label: 'Connect to Host...',
        ),
        AdaptiveMenuAction(
          value: _NewTabAction.deviceLink,
          itemKey: const Key('new_tab_menu_device_link'),
          icon: isMobilePlatform ? LucideIcons.scanQrCode : LucideIcons.qrCode,
          label: isMobilePlatform
              ? 'Scan Device Link QR'
              : 'Show Device Link QR',
        ),
      ],
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _NewTabAction.localShell:
        ref.read(terminalTabsProvider.notifier).openLocalTab();
      case _NewTabAction.connectToHost:
        _showSelectHostModal(this.context, ref);
      case _NewTabAction.deviceLink:
        if (isMobilePlatform) {
          unawaited(this.context.push('/device-link/scan'));
        } else {
          unawaited(_openDeviceLinkQr(this.context, ref));
        }
    }
  }

  /// Decrypts the identity attached to [host], if any.
  ///
  /// Returns `(ok: false, ...)` when the stored credentials cannot be read, so
  /// callers abort instead of connecting with silently missing credentials;
  /// the failure is surfaced as a toast here.
  Future<({bool ok, IdentityModel? identity})> _resolveIdentity(
    HostModel host,
  ) async {
    if (host.identityId == null) return (ok: true, identity: null);
    try {
      final identity = await ref
          .read(identitiesProvider.notifier)
          .getDecryptedIdentity(host.identityId!);
      return (ok: true, identity: identity);
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text('Cannot read stored credentials: $e'),
          ),
        );
      }
      return (ok: false, identity: null);
    }
  }

  /// Resolves the host's identity and opens an SSH tab.
  ///
  /// Host key verification is routed through [HostKeyPromptDialog] so the user
  /// actually gets asked.
  Future<void> _connectToHost(HostModel host) async {
    final resolved = await _resolveIdentity(host);
    if (!resolved.ok) return;

    await ref
        .read(terminalTabsProvider.notifier)
        .openTabForHost(
          host,
          identity: resolved.identity,
          onHostKeyPrompt: _promptHostKey,
        );
  }

  /// Splits [paneId] into a pane running on a different host: asks for the
  /// split direction first, then for the host.
  Future<void> _startSplitWithHost(String paneId) async {
    final direction = await _askSplitDirection();
    if (direction == null || !mounted) return;
    _showSelectHostModal(
      context,
      ref,
      onSelect: (host) => _splitWithHost(paneId, direction, host),
    );
  }

  Future<Axis?> _askSplitDirection() {
    return showAdaptivePanel<Axis>(
      context: context,
      title: 'Split Direction',
      desktopWidth: 340,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('split_host_direction_vertical'),
            leading: const Icon(LucideIcons.columns2, size: 18),
            title: const Text('Side by Side'),
            onTap: () => Navigator.of(ctx).pop(Axis.horizontal),
          ),
          ListTile(
            key: const Key('split_host_direction_horizontal'),
            leading: const Icon(LucideIcons.rows2, size: 18),
            title: const Text('Top / Bottom'),
            onTap: () => Navigator.of(ctx).pop(Axis.vertical),
          ),
        ],
      ),
    );
  }

  Future<void> _splitWithHost(
    String paneId,
    Axis direction,
    HostModel host,
  ) async {
    final resolved = await _resolveIdentity(host);
    if (!resolved.ok) return;

    await ref
        .read(terminalTabsProvider.notifier)
        .splitTab(
          paneId,
          direction: direction,
          host: host,
          identity: resolved.identity,
          onHostKeyPrompt: _promptHostKey,
        );
  }

  /// Saves every open tab and split pane as a named template.
  Future<void> _saveCurrentLayoutAsTemplate() async {
    final tabsState = ref.read(terminalTabsProvider);
    if (tabsState.tabs.isEmpty) return;

    final tabs = tabsState.tabs.where((t) => t.splitParentId == null).length;
    final splits = tabsState.tabs.length - tabs;
    final summary = splits == 0
        ? 'Saving $tabs ${tabs == 1 ? 'tab' : 'tabs'}.'
        : 'Saving $tabs ${tabs == 1 ? 'tab' : 'tabs'} and $splits '
              '${splits == 1 ? 'split pane' : 'split panes'}.';

    final details = await SaveTemplateDialog.show(context, summary: summary);
    if (details == null || !mounted) return;

    final template = await ref
        .read(templatesProvider.notifier)
        .saveCurrentLayout(
          name: details.name,
          description: details.description,
        );
    if (!mounted) return;

    ShadToaster.of(context).show(
      template == null
          ? const ShadToast.destructive(
              description: Text('Nothing open to save as a template.'),
            )
          : ShadToast(description: Text('Saved "${template.name}".')),
    );
  }

  /// Reopens a saved layout alongside whatever is already open.
  ///
  /// Panes that cannot be recreated — a deleted host, unreadable credentials —
  /// are reported rather than failing the whole run.
  Future<void> _runTemplate(TemplateModel template) async {
    final result = await ref
        .read(templatesProvider.notifier)
        .runTemplate(
          template,
          resolveIdentity: _resolveIdentity,
          onHostKeyPrompt: _promptHostKey,
        );
    if (!mounted) return;

    if (result.isComplete) {
      ShadToaster.of(context).show(
        ShadToast(
          description: Text(
            'Opened "${template.name}" — ${result.openedPanes} '
            '${result.openedPanes == 1 ? 'pane' : 'panes'}.',
          ),
        ),
      );
      return;
    }

    ShadToaster.of(context).show(
      ShadToast.destructive(
        title: Text(
          result.openedPanes == 0
              ? 'Could not run "${template.name}"'
              : 'Ran "${template.name}" with skipped panes',
        ),
        description: Text(result.warnings.join('\n')),
      ),
    );
  }

  Future<bool> _promptHostKey(
    String hostname,
    int port,
    String keyType,
    String fingerprint,
    HostKeyVerificationStatus status,
  ) async {
    if (!mounted) return false;
    final approved = await HostKeyPromptDialog.show(
      context,
      hostname: hostname,
      port: port,
      keyType: keyType,
      fingerprint: fingerprint,
      status: status,
    );
    return approved ?? false;
  }

  /// Host picker sheet. [onSelect] runs after the sheet is dismissed, so the
  /// same list drives both "new tab" and "split with another host".
  void _showSelectHostModal(
    BuildContext context,
    WidgetRef ref, {
    Future<void> Function(HostModel host)? onSelect,
  }) {
    showAdaptivePanel<void>(
      context: context,
      title: 'Connect to Host',
      desktopHeight: 420,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final hostsAsync = ref.watch(hostsProvider);
            return hostsAsync.when(
              data: (hosts) {
                if (hosts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(
                      child: Text('No hosts available. Create one first.'),
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: hosts.length,
                  itemBuilder: (context, index) {
                    final host = hosts[index];
                    return ListTile(
                      leading: const Icon(LucideIcons.server, size: 18),
                      title: Text(host.label),
                      subtitle: Text('${host.hostname}:${host.port}'),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        await (onSelect ?? _connectToHost)(host);
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Error loading hosts: $e')),
            );
          },
        );
      },
    );
  }
}

/// The rows of the "+" menu, so the choice survives the modal being a dropdown
/// on one host and a sheet on another.
enum _NewTabAction { localShell, connectToHost, deviceLink }

/// Persistent one-row snippet strip under the panes.
///
/// The wireframe keeps it visible rather than behind a menu, and shows the
/// `${INPUT:…}` placeholders inline so a parameterised command is recognisable
/// before it is sent.
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
          height: boxed ? _kTabBarHeight : 32,
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

class _SnippetDrawer extends ConsumerWidget {
  final void Function(String code) onSend;

  const _SnippetDrawer({required this.onSend});

  Future<void> _run(BuildContext context, SnippetModel snippet) async {
    final variables = SnippetVariableParser.extractVariables(snippet.code);
    var values = <String, String>{};
    if (variables.isNotEmpty) {
      final entered = await VariableInputDialog.show(
        context,
        variables: variables,
        title: 'Fill variables for "${snippet.title}"',
      );
      if (entered == null) return;
      values = entered;
    }
    onSend(SnippetVariableParser.substituteVariables(snippet.code, values));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    final snippets =
        ref.watch(snippetsProvider).value ?? const <SnippetModel>[];
    if (snippets.isEmpty) return const SizedBox.shrink();
    final selectedCount = ref.watch(
      terminalTabsProvider.select((s) => s.selectedPaneIds.length),
    );
    final sendLabel = selectedCount >= 2
        ? 'SNIPPET · SEND TO $selectedCount PANES'
        : 'SNIPPET · SEND TO ACTIVE PANE';

    return Container(
      key: const Key('terminal_snippet_drawer'),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                sendLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: tokens.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 26,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: snippets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final snippet = snippets[index];
                final firstLine = snippet.code.split('\n').first.trim();
                return InkWell(
                  key: Key('snippet_chip_${snippet.id}'),
                  onTap: () => _run(context, snippet),
                  borderRadius: BorderRadius.circular(tokens.radiusPill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(tokens.radiusPill),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Text(
                      firstLine.isEmpty ? snippet.title : firstLine,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
