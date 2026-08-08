import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/terly_tokens.dart';
import '../../../../app/widgets/terly_ui.dart';
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
import '../dialogs/host_key_prompt_dialog.dart';
import '../notifiers/terminal_tabs_notifier.dart';
import '../screens/terminal_screen.dart';
import '../widgets/resizable_split.dart';
import '../../domain/models/terminal_tab_session.dart';

/// Below this bar width the trailing actions collapse into one overflow menu.
const double _kTabBarCompactWidth = 620;

/// A trailing tab-bar action, rendered either as an [IconButton] or as a row in
/// the compact overflow menu.
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
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Column(
            children: [
              // Top Tab Bar
              _buildTabBar(context, ref, tabsState, activeRootTab),
              // Tab Content / Body
              Expanded(
                child: activeRootTab == null
                    ? _buildEmptyState(context, ref)
                    : _buildTabBody(context, ref, tabsState, activeRootTab),
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
    final tokens = TerlyTokens.resolve(context);
    final rootTabs = tabsState.tabs
        .where((t) => t.splitParentId == null)
        .toList();

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
    ];

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _kTabBarCompactWidth;
          return Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: rootTabs.length,
                  itemBuilder: (context, index) {
                    final tab = rootTabs[index];
                    final isActive = tab.id == activeRootTab?.id;
                    // Tab identity is the host name plus a state dot. The old
                    // colour-coded tab edge is gone: the wireframe wants text to
                    // do the distinguishing so eight tabs stay readable.
                    final dotState = tab.errorMessage != null
                        ? TerlyDotState.error
                        : tab.isConnecting
                        ? TerlyDotState.idle
                        : tab.isConnected
                        ? TerlyDotState.online
                        : TerlyDotState.offline;

                    return Semantics(
                      label: 'Tab ${tab.title}',
                      selected: isActive,
                      button: true,
                      child: InkWell(
                        onTap: () => ref
                            .read(terminalTabsProvider.notifier)
                            .setActiveTab(tab.id),
                        child: AnimatedContainer(
                          duration: tokens.motionFast,
                          key: Key('tab_header_${tab.id}'),
                          constraints: BoxConstraints(
                            minWidth: compact ? 96 : 120,
                            maxWidth: 230,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: isActive
                                ? tokens.surfaceRaised
                                : Colors.transparent,
                            border: Border(
                              bottom: BorderSide(
                                color: isActive
                                    ? tokens.brand
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TerlyStatusDot(state: dotState, size: 6),
                              const SizedBox(width: 7),
                              Icon(
                                tab.sessionType == TerminalSessionType.ssh
                                    ? LucideIcons.terminal
                                    : LucideIcons.monitor,
                                size: 15,
                                color: isActive
                                    ? tokens.brand
                                    : tokens.textMuted,
                              ),
                              const SizedBox(width: 6),
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
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
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
                                    size: 13,
                                    color: tokens.textMuted,
                                  ),
                                ),
                              ),
                            ],
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
                for (final action in actions)
                  IconButton(
                    key: action.buttonKey,
                    icon: Icon(action.icon, size: 17),
                    tooltip: action.label,
                    onPressed: action.onPressed,
                  ),
              // New Tab Button
              IconButton(
                key: const Key('new_tab_button'),
                icon: Icon(
                  LucideIcons.plus,
                  size: 18,
                  color: tokens.textPrimary,
                ),
                tooltip: 'New Tab',
                onPressed: () => _showNewTabMenu(context, ref),
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
    final tokens = TerlyTokens.resolve(context);
    return _buildSessionTree(
      context,
      ref,
      activeRootTab,
      tabsState.tabs,
      tokens,
      paneOrder: _paneOrder(tabsState, activeRootTab),
      activePaneId: tabsState.activeTabId,
      selectedPaneIds: tabsState.selectedPaneIds,
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
    final connectionLabel = pane.errorMessage != null
        ? 'error'
        : pane.isConnecting
        ? 'connecting'
        : pane.isConnected
        ? 'connected'
        : 'disconnected';

    return TerlyStatusBar(
      segments: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TerlyStatusDot(
              state: pane.errorMessage != null
                  ? TerlyDotState.error
                  : pane.isConnected
                  ? TerlyDotState.online
                  : TerlyDotState.offline,
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

  Widget _buildSessionTree(
    BuildContext context,
    WidgetRef ref,
    TerminalTabSession session,
    List<TerminalTabSession> allTabs,
    TerlyTokens tokens, {
    required List<String> paneOrder,
    required String? activePaneId,
    required Set<String> selectedPaneIds,
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
      );
      // A single-pane tab needs no header; once the tab is split every pane
      // gets one, because the header is what names the snippet target.
      if (paneOrder.length < 2) {
        return screen;
      }
      final paneNumber = paneOrder.indexOf(paneSession.id) + 1;
      final isActivePane = paneSession.id == activePaneId;
      final isBroadcastSelected = selectedPaneIds.contains(paneSession.id);
      final paneLabel = isBroadcastSelected
          ? 'pane $paneNumber · broadcast'
          : isActivePane
          ? 'pane $paneNumber · active'
          : 'pane $paneNumber';
      final paneLabelColor = isBroadcastSelected || isActivePane
          ? tokens.brand
          : tokens.textMuted;
      return Column(
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isBroadcastSelected
                  ? tokens.brand.withValues(alpha: 0.08)
                  : tokens.surfaceRaised,
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Row(
              children: [
                Icon(
                  paneSession.sessionType == TerminalSessionType.ssh
                      ? LucideIcons.terminal
                      : LucideIcons.monitor,
                  size: 13,
                  color: isBroadcastSelected ? tokens.brand : tokens.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    paneSession.title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: tokens.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  paneLabel,
                  key: Key('pane_label_${paneSession.id}'),
                  style: TextStyle(fontSize: 10, color: paneLabelColor),
                ),
                const SizedBox(width: 8),
                if (paneSession.splitParentId != null)
                  Semantics(
                    label: 'Close split pane ${paneSession.title}',
                    button: true,
                    child: InkWell(
                      key: Key('close_split_${paneSession.id}'),
                      onTap: () => ref
                          .read(terminalTabsProvider.notifier)
                          .closeTab(paneSession.id),
                      child: Padding(
                        padding: const EdgeInsets.all(2.0),
                        child: Icon(
                          LucideIcons.x,
                          size: 13,
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: screen),
        ],
      );
    }

    Widget resultWidget = buildSinglePane(session);

    if (children.isEmpty) {
      return resultWidget;
    }

    for (final child in children) {
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
        dividerColor: tokens.border,
        dividerKey: Key('split_divider_${child.id}'),
        onRatioChanged: (ratio) => ref
            .read(terminalTabsProvider.notifier)
            .setSplitRatio(child.id, ratio),
      );
    }

    return resultWidget;
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return TerlyEmptyState(
      icon: LucideIcons.squareTerminal,
      title: 'No Active Terminal Sessions',
      description: isMobilePlatform
          ? 'Select a remote SSH server to connect.'
          : 'Open a local shell or select a remote SSH server to connect.',
      actions: [
        if (supportsLocalShell)
          ShadButton(
            key: const Key('empty_open_local_button'),
            leading: const Icon(LucideIcons.monitor, size: 16),
            onPressed: () =>
                ref.read(terminalTabsProvider.notifier).openLocalTab(),
            child: const Text('Open Local Shell'),
          ),
        ShadButton.outline(
          key: const Key('empty_select_host_button'),
          leading: const Icon(LucideIcons.server, size: 16),
          onPressed: () => _showSelectHostModal(context, ref),
          child: const Text('Connect to Host'),
        ),
      ],
    );
  }

  void _showNewTabMenu(BuildContext context, WidgetRef ref) {
    final tokens = TerlyTokens.resolve(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: tokens.surface,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (supportsLocalShell)
            ListTile(
              key: const Key('new_tab_menu_local'),
              leading: const Icon(LucideIcons.monitor, size: 18),
              title: const Text('Local Shell'),
              onTap: () {
                Navigator.of(ctx).pop();
                ref.read(terminalTabsProvider.notifier).openLocalTab();
              },
            ),
          ListTile(
            key: const Key('new_tab_menu_host'),
            leading: const Icon(LucideIcons.server, size: 18),
            title: const Text('Connect to Host...'),
            onTap: () {
              Navigator.of(ctx).pop();
              _showSelectHostModal(context, ref);
            },
          ),
        ],
      ),
    );
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
    final tokens = TerlyTokens.resolve(context);
    return showModalBottomSheet<Axis>(
      context: context,
      showDragHandle: true,
      backgroundColor: tokens.surface,
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
    final tokens = TerlyTokens.resolve(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: tokens.surface,
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

/// Persistent one-row snippet strip under the panes.
///
/// The wireframe keeps it visible rather than behind a menu, and shows the
/// `${INPUT:…}` placeholders inline so a parameterised command is recognisable
/// before it is sent.
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
    final tokens = TerlyTokens.resolve(context);
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
