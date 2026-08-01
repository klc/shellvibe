import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/network/ssh_session_manager.dart';
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

  @override
  Widget build(BuildContext context) {
    final tabsState = ref.watch(terminalTabsProvider);
    final activeTab = tabsState.activeTab;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyT, meta: true): () {
            ref.read(terminalTabsProvider.notifier).openLocalTab();
          },
          const SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
            ref.read(terminalTabsProvider.notifier).openLocalTab();
          },
          const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () {
            if (activeTab != null) {
              ref.read(terminalTabsProvider.notifier).closeTab(activeTab.id);
            }
          },
          const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
            if (activeTab != null) {
              ref.read(terminalTabsProvider.notifier).closeTab(activeTab.id);
            }
          },
        },
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Column(
            children: [
              // Top Tab Bar
              _buildTabBar(context, ref, tabsState),
              // Tab Content / Body
              Expanded(
                child: activeTab == null
                    ? _buildEmptyState(context, ref)
                    : _buildTabBody(context, ref, tabsState, activeTab),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(BuildContext context, WidgetRef ref, TerminalTabsState tabsState) {
    final shadTheme = ShadTheme.of(context);
    final colorScheme = shadTheme.colorScheme;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colorScheme.card,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.border,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabsState.tabs.length,
              itemBuilder: (context, index) {
                final tab = tabsState.tabs[index];
                final isActive = tab.id == tabsState.activeTabId;

                return Semantics(
                  label: 'Tab ${tab.title}',
                  selected: isActive,
                  button: true,
                  child: GestureDetector(
                    onTap: () =>
                        ref.read(terminalTabsProvider.notifier).setActiveTab(tab.id),
                    child: Container(
                      key: Key('tab_header_${tab.id}'),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive ? colorScheme.muted : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: isActive ? colorScheme.primary : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            tab.sessionType == TerminalSessionType.ssh
                                ? Icons.terminal
                                : Icons.computer,
                            size: 16,
                            color: isActive ? colorScheme.primary : colorScheme.mutedForeground,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            tab.title,
                            style: TextStyle(
                              color: isActive ? colorScheme.foreground : colorScheme.mutedForeground,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
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
                                Icons.close,
                                size: 14,
                                color: colorScheme.mutedForeground,
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
          // Split Pane Action Button
          if (tabsState.activeTabId != null)
            IconButton(
              key: const Key('split_tab_button'),
              icon: Icon(Icons.vertical_split, size: 18, color: colorScheme.mutedForeground),
              tooltip: 'Split Pane',
              onPressed: () {
                ref
                    .read(terminalTabsProvider.notifier)
                    .splitTab(tabsState.activeTabId!, direction: Axis.horizontal);
              },
            ),
          // New Tab Button
          IconButton(
            key: const Key('new_tab_button'),
            icon: Icon(Icons.add, size: 20, color: colorScheme.foreground),
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
    TerminalTabSession activeTab,
  ) {
    final colorScheme = ShadTheme.of(context).colorScheme;

    // Check if active tab has split children
    final splits = tabsState.tabs.where((t) => t.splitParentId == activeTab.id).toList();

    if (splits.isEmpty) {
      return TerminalScreen(session: activeTab);
    }

    // Render Side-by-Side Split View
    return Row(
      children: [
        Expanded(child: TerminalScreen(session: activeTab)),
        VerticalDivider(width: 2, color: colorScheme.border),
        ...splits.map(
          (splitTab) => Expanded(
            child: TerminalScreen(session: splitTab),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    final colorScheme = ShadTheme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.terminal,
            size: 64,
            color: colorScheme.mutedForeground,
          ),
          const SizedBox(height: 16),
          Text(
            'No Active Terminal Sessions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Open a local shell or select a remote SSH server to connect.',
            style: TextStyle(color: colorScheme.mutedForeground),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              ShadButton(
                key: const Key('empty_open_local_button'),
                leading: const Icon(Icons.computer, size: 18),
                onPressed: () =>
                    ref.read(terminalTabsProvider.notifier).openLocalTab(),
                child: const Text('Open Local Shell'),
              ),
              ShadButton.outline(
                key: const Key('empty_select_host_button'),
                leading: const Icon(Icons.dns, size: 18),
                onPressed: () => _showSelectHostModal(context, ref),
                child: const Text('Connect to Host'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showNewTabMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('new_tab_menu_local'),
            leading: const Icon(Icons.computer),
            title: const Text('Local Shell'),
            onTap: () {
              Navigator.of(ctx).pop();
              ref.read(terminalTabsProvider.notifier).openLocalTab();
            },
          ),
          ListTile(
            key: const Key('new_tab_menu_host'),
            leading: const Icon(Icons.dns),
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

    await ref.read(terminalTabsProvider.notifier).openTabForHost(
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
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final hostsAsync = ref.watch(hostsProvider);
            return hostsAsync.when(
              data: (hosts) {
                if (hosts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(child: Text('No hosts available. Create one first.')),
                  );
                }
                return ListView.builder(
                  itemCount: hosts.length,
                  itemBuilder: (context, index) {
                    final host = hosts[index];
                    return ListTile(
                      leading: const Icon(Icons.dns),
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
