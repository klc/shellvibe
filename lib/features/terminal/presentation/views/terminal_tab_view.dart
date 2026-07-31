import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../notifiers/terminal_tabs_notifier.dart';
import '../screens/terminal_screen.dart';
import '../../domain/models/terminal_tab_session.dart';

class TerminalTabView extends ConsumerWidget {
  const TerminalTabView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabsState = ref.watch(terminalTabsNotifierProvider);
    final activeTab = tabsState.activeTab;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
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
    );
  }

  Widget _buildTabBar(BuildContext context, WidgetRef ref, TerminalTabsState tabsState) {
    return Container(
      height: 40,
      color: const Color(0xFF181825),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabsState.tabs.length,
              itemBuilder: (context, index) {
                final tab = tabsState.tabs[index];
                final isActive = tab.id == tabsState.activeTabId;

                return GestureDetector(
                  onTap: () =>
                      ref.read(terminalTabsNotifierProvider.notifier).setActiveTab(tab.id),
                  child: Container(
                    key: Key('tab_header_${tab.id}'),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFF24273A) : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(
                          color: isActive ? const Color(0xFF8AADF4) : Colors.transparent,
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
                          color: isActive ? const Color(0xFF8AADF4) : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tab.title,
                          style: TextStyle(
                            color: isActive ? Colors.white : Colors.grey,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          key: Key('close_tab_${tab.id}'),
                          onTap: () => ref
                              .read(terminalTabsNotifierProvider.notifier)
                              .closeTab(tab.id),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
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
              icon: const Icon(Icons.vertical_split, size: 18, color: Colors.grey),
              tooltip: 'Split Pane',
              onPressed: () {
                ref
                    .read(terminalTabsNotifierProvider.notifier)
                    .splitTab(tabsState.activeTabId!, direction: Axis.horizontal);
              },
            ),
          // New Tab Button
          IconButton(
            key: const Key('new_tab_button'),
            icon: const Icon(Icons.add, size: 20, color: Colors.white),
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
    // Check if active tab has split children
    final splits = tabsState.tabs.where((t) => t.splitParentId == activeTab.id).toList();

    if (splits.isEmpty) {
      return TerminalScreen(session: activeTab);
    }

    // Render Side-by-Side Split View
    return Row(
      children: [
        Expanded(child: TerminalScreen(session: activeTab)),
        const VerticalDivider(width: 2, color: Color(0xFF181825)),
        ...splits.map(
          (splitTab) => Expanded(
            child: TerminalScreen(session: splitTab),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.terminal,
            size: 64,
            color: Color(0xFF5B6078),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Active Terminal Sessions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Open a local shell or select a remote SSH server to connect.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                key: const Key('empty_open_local_button'),
                icon: const Icon(Icons.computer),
                label: const Text('Open Local Shell'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8AADF4),
                  foregroundColor: const Color(0xFF1E1E2E),
                ),
                onPressed: () =>
                    ref.read(terminalTabsNotifierProvider.notifier).openLocalTab(),
              ),
              OutlinedButton.icon(
                key: const Key('empty_select_host_button'),
                icon: const Icon(Icons.dns),
                label: const Text('Connect to Host'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8AADF4),
                ),
                onPressed: () => _showSelectHostModal(context, ref),
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
              ref.read(terminalTabsNotifierProvider.notifier).openLocalTab();
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

  void _showSelectHostModal(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final hostsAsync = ref.watch(hostsNotifierProvider);
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

                        // Fetch assigned identity if present
                        IdentityModel? identity;
                        if (host.identityId != null) {
                          identity = await ref
                              .read(identitiesNotifierProvider.notifier)
                              .getDecryptedIdentity(host.identityId!);
                        }

                        ref.read(terminalTabsNotifierProvider.notifier).openTabForHost(
                              host,
                              identity: identity,
                            );
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
