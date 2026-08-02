import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/terly_tokens.dart';
import '../../../../app/widgets/terly_ui.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../dialogs/host_key_prompt_dialog.dart';
import '../notifiers/terminal_tabs_notifier.dart';
import '../screens/terminal_screen.dart';
import '../../domain/models/terminal_tab_session.dart';

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
    final rootTabs =
        tabsState.tabs.where((t) => t.splitParentId == null).toList();

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: rootTabs.length,
              itemBuilder: (context, index) {
                final tab = rootTabs[index];
                final isActive = tab.id == activeRootTab?.id;
                final isProduction = tab.title.toLowerCase().contains('prod');
                final statusColor = tab.errorMessage != null
                    ? tokens.danger
                    : tab.isConnecting
                    ? tokens.warning
                    : tab.isConnected
                    ? tokens.success
                    : tokens.textMuted;

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
                      constraints: const BoxConstraints(
                        minWidth: 120,
                        maxWidth: 230,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isActive
                            ? tokens.surfaceRaised
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: isActive ? tokens.brand : Colors.transparent,
                            width: 2,
                          ),
                          left: BorderSide(
                            color: isProduction
                                ? tokens.danger
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Icon(
                            tab.sessionType == TerminalSessionType.ssh
                                ? LucideIcons.terminal
                                : LucideIcons.monitor,
                            size: 15,
                            color: isActive ? tokens.brand : tokens.textMuted,
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
          // Split Pane Action Buttons (Vertical & Horizontal Split)
          if (activeRootTab != null) ...[
            IconButton(
              key: const Key('split_vertical_button'),
              icon: const Icon(LucideIcons.columns2, size: 17),
              tooltip: 'Split Vertically (Side by Side)',
              onPressed: () {
                final targetId = tabsState.activeTabId ?? activeRootTab.id;
                ref.read(terminalTabsProvider.notifier).splitTab(
                      targetId,
                      direction: Axis.horizontal,
                    );
              },
            ),
            IconButton(
              key: const Key('split_horizontal_button'),
              icon: const Icon(LucideIcons.rows2, size: 17),
              tooltip: 'Split Horizontally (Top/Bottom)',
              onPressed: () {
                final targetId = tabsState.activeTabId ?? activeRootTab.id;
                ref.read(terminalTabsProvider.notifier).splitTab(
                      targetId,
                      direction: Axis.vertical,
                    );
              },
            ),
          ],
          // New Tab Button
          IconButton(
            key: const Key('new_tab_button'),
            icon: Icon(LucideIcons.plus, size: 18, color: tokens.textPrimary),
            tooltip: 'New Tab',
            onPressed: () => _showNewTabMenu(context, ref),
          ),
        ],
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
    );
  }

  Widget _buildSessionTree(
    BuildContext context,
    WidgetRef ref,
    TerminalTabSession session,
    List<TerminalTabSession> allTabs,
    TerlyTokens tokens,
  ) {
    final children =
        allTabs.where((t) => t.splitParentId == session.id).toList();

    Widget buildSinglePane(TerminalTabSession paneSession) {
      if (paneSession.splitParentId == null) {
        return TerminalScreen(session: paneSession);
      }
      return Column(
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Row(
              children: [
                Icon(
                  paneSession.sessionType == TerminalSessionType.ssh
                      ? LucideIcons.terminal
                      : LucideIcons.monitor,
                  size: 13,
                  color: tokens.textMuted,
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
          Expanded(child: TerminalScreen(session: paneSession)),
        ],
      );
    }

    Widget resultWidget = buildSinglePane(session);

    if (children.isEmpty) {
      return resultWidget;
    }

    for (final child in children) {
      final childTree = _buildSessionTree(context, ref, child, allTabs, tokens);
      final direction = child.splitDirection ?? Axis.horizontal;
      if (direction == Axis.vertical) {
        // Yatay bölme (Horizontal split line): Panes stacked top-to-bottom in a Column
        resultWidget = Column(
          children: [
            Expanded(child: resultWidget),
            Container(height: 2, color: tokens.border),
            Expanded(child: childTree),
          ],
        );
      } else {
        // Dikey bölme (Vertical split line): Panes side-by-side in a Row
        resultWidget = Row(
          children: [
            Expanded(child: resultWidget),
            VerticalDivider(width: 2, color: tokens.border),
            Expanded(child: childTree),
          ],
        );
      }
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

  /// Resolves the host's identity and opens an SSH tab.
  ///
  /// Decryption failures are surfaced instead of connecting with silently
  /// missing credentials, and host key verification is routed through
  /// [HostKeyPromptDialog] so the user actually gets asked.
  Future<void> _connectToHost(HostModel host) async {
    IdentityModel? identity;
    if (host.identityId != null) {
      try {
        identity = await ref
            .read(identitiesProvider.notifier)
            .getDecryptedIdentity(host.identityId!);
      } catch (e) {
        if (!mounted) return;
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text('Cannot read stored credentials: $e'),
          ),
        );
        return;
      }
    }

    await ref
        .read(terminalTabsProvider.notifier)
        .openTabForHost(
          host,
          identity: identity,
          onHostKeyPrompt: _promptHostKey,
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

  void _showSelectHostModal(BuildContext context, WidgetRef ref) {
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
                        await _connectToHost(host);
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
