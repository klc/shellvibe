import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../terminal/presentation/dialogs/host_key_prompt_dialog.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../dialogs/host_form_dialog.dart';
import '../dialogs/host_group_form_dialog.dart';
import '../notifiers/host_groups_notifier.dart';
import '../notifiers/hosts_notifier.dart';
import '../../domain/models/host_group_model.dart';
import '../../domain/models/host_model.dart';

class HostsScreen extends ConsumerStatefulWidget {
  final void Function(HostModel host)? onConnectHost;

  const HostsScreen({super.key, this.onConnectHost});

  @override
  ConsumerState<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends ConsumerState<HostsScreen> {
  String _searchQuery = '';
  final Set<String> _connectingHostIds = {};

  @override
  Widget build(BuildContext context) {
    final hostsAsync = ref.watch(hostsProvider);
    final groupsAsync = ref.watch(hostGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hosts & Servers'),
        actions: [
          IconButton(
            key: const Key('add_group_button'),
            icon: const Icon(Icons.create_new_folder),
            tooltip: 'Add Group',
            onPressed: () => _openGroupForm(context),
          ),
          IconButton(
            key: const Key('add_host_button'),
            icon: const Icon(Icons.add),
            tooltip: 'Add Host',
            onPressed: () => _openHostForm(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              key: const Key('hosts_search_input'),
              decoration: const InputDecoration(
                hintText: 'Search hosts by label, hostname, protocol...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val.toLowerCase());
              },
            ),
          ),
          Expanded(
            child: hostsAsync.when(
              data: (hosts) {
                final filtered = hosts.where((h) {
                  return h.label.toLowerCase().contains(_searchQuery) ||
                      h.hostname.toLowerCase().contains(_searchQuery) ||
                      (h.username ?? '').toLowerCase().contains(_searchQuery) ||
                      h.protocol.toLowerCase().contains(_searchQuery);
                }).toList();

                return groupsAsync.when(
                  data: (groups) {
                    if (hosts.isEmpty && groups.isEmpty) {
                      return const Center(
                        child: Text('No hosts or groups configured.'),
                      );
                    }

                    final categorized = _buildCategorizedItems(
                      filtered,
                      groups,
                      includeEmptyGroups: _searchQuery.isEmpty,
                    );
                    final items = categorized.items;

                    if (items.isEmpty) {
                      return const Center(
                        child: Text('No hosts match your search.'),
                      );
                    }

                    return ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];

                        if (item is HostGroupModel) {
                          final groupHosts =
                              categorized.groupedHosts[item.id] ?? const [];
                          return _GroupExpansionTile(
                            key: ValueKey('group_${item.id}'),
                            group: item,
                            hosts: groupHosts,
                            onEditHost: (h) =>
                                _openHostForm(context, initialHost: h),
                            onDeleteHost: (h) => _deleteHost(context, h),
                            onConnectHost: _onConnectHost,
                            onEditGroup: (g) =>
                                _openGroupForm(context, initialGroup: g),
                            onDeleteGroup: (g) => _deleteGroup(context, g),
                            connectingHostIds: _connectingHostIds,
                          );
                        } else if (item is HostModel) {
                          return _HostTile(
                            key: ValueKey(item.id),
                            host: item,
                            isConnecting: _connectingHostIds.contains(item.id),
                            onEdit: () =>
                                _openHostForm(context, initialHost: item),
                            onDelete: () => _deleteHost(context, item),
                            onConnect: () => _onConnectHost(item),
                          );
                        }

                        return const SizedBox.shrink();
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, s) =>
                      Center(child: Text('Error loading groups: $e')),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => Center(child: Text('Error loading hosts: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _defaultConnectHost(HostModel host) async {
    IdentityModel? identity;
    if (host.identityId != null) {
      try {
        identity = await ref
            .read(identitiesProvider.notifier)
            .getDecryptedIdentity(host.identityId!);
      } catch (e) {
        if (mounted) {
          ShadToaster.of(context).show(
            ShadToast.destructive(
              description: Text('Cannot read stored credentials: $e'),
            ),
          );
        }
        return;
      }
    }

    await ref.read(terminalTabsProvider.notifier).openTabForHost(
          host,
          identity: identity,
          onHostKeyPrompt: (hostname, port, keyType, fingerprint, status) async {
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
          },
        );

    if (mounted) {
      GoRouter.maybeOf(context)?.go('/terminal');
    }
  }

  Future<void> _onConnectHost(HostModel host) async {
    if (_connectingHostIds.contains(host.id)) return;
    setState(() => _connectingHostIds.add(host.id));
    try {
      if (widget.onConnectHost != null) {
        widget.onConnectHost!(host);
      } else {
        await _defaultConnectHost(host);
      }
    } finally {
      if (mounted) {
        setState(() => _connectingHostIds.remove(host.id));
      }
    }
  }

  void _openHostForm(BuildContext context, {HostModel? initialHost}) {
    showDialog(
      context: context,
      builder: (ctx) => HostFormDialog(initialHost: initialHost),
    );
  }

  void _openGroupForm(BuildContext context, {HostGroupModel? initialGroup}) {
    showDialog(
      context: context,
      builder: (ctx) => HostGroupFormDialog(initialGroup: initialGroup),
    );
  }

  Future<void> _deleteHost(BuildContext context, HostModel host) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog.alert(
        title: const Text('Delete Host'),
        description: Text('Are you sure you want to delete "${host.label}"?'),
        actions: [
          ShadButton.outline(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ShadButton.destructive(
            child: const Text('Delete'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(hostsProvider.notifier).deleteHost(host.id);
    }
  }

  Future<void> _deleteGroup(BuildContext context, HostGroupModel group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog.alert(
        title: const Text('Delete Group'),
        description: Text(
          'Are you sure you want to delete group "${group.name}"? Hosts inside will be unassigned.',
        ),
        actions: [
          ShadButton.outline(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ShadButton.destructive(
            child: const Text('Delete'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(hostGroupsProvider.notifier).deleteGroup(group.id);
    }
  }

  ({List<Object> items, Map<String, List<HostModel>> groupedHosts}) _buildCategorizedItems(
    List<HostModel> filteredHosts,
    List<HostGroupModel> groups, {
    required bool includeEmptyGroups,
  }) {
    final items = <Object>[];
    final groupedHosts = <String, List<HostModel>>{};
    final ungroupedHosts = <HostModel>[];

    for (final host in filteredHosts) {
      final groupId = host.groupId;
      if (groupId == null) {
        ungroupedHosts.add(host);
      } else {
        groupedHosts.putIfAbsent(groupId, () => []).add(host);
      }
    }

    for (final group in groups) {
      if (includeEmptyGroups || groupedHosts.containsKey(group.id)) {
        items.add(group);
      }
    }

    items.addAll(ungroupedHosts);

    return (items: items, groupedHosts: groupedHosts);
  }
}

class _GroupExpansionTile extends StatelessWidget {
  final HostGroupModel group;
  final List<HostModel> hosts;
  final void Function(HostModel) onEditHost;
  final void Function(HostModel) onDeleteHost;
  final void Function(HostModel) onConnectHost;
  final void Function(HostGroupModel) onEditGroup;
  final void Function(HostGroupModel) onDeleteGroup;
  final Set<String> connectingHostIds;

  const _GroupExpansionTile({
    super.key,
    required this.group,
    required this.hosts,
    required this.onEditHost,
    required this.onDeleteHost,
    required this.onConnectHost,
    required this.onEditGroup,
    required this.onDeleteGroup,
    required this.connectingHostIds,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: theme.colorScheme.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ExpansionTile(
          leading: Icon(Icons.folder, color: primaryColor),
          title: Text(
            group.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text('${hosts.length} server(s)'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: () => onEditGroup(group),
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
                onPressed: () => onDeleteGroup(group),
              ),
            ],
          ),
          children: hosts
              .map(
                (h) => _HostTile(
                  key: ValueKey(h.id),
                  host: h,
                  isConnecting: connectingHostIds.contains(h.id),
                  onEdit: () => onEditHost(h),
                  onDelete: () => onDeleteHost(h),
                  onConnect: () => onConnectHost(h),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _HostTile extends StatelessWidget {
  final HostModel host;
  final bool isConnecting;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onConnect;

  const _HostTile({
    super.key,
    required this.host,
    this.isConnecting = false,
    required this.onEdit,
    required this.onDelete,
    this.onConnect,
  });

  IconData _getProtocolIcon() {
    switch (host.protocol) {
      case 'ssh':
        return Icons.terminal;
      case 'mosh':
        return Icons.cell_tower;
      case 'local':
        return Icons.computer;
      case 'serial':
        return Icons.usb;
      default:
        return Icons.dns;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: theme.colorScheme.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: primaryColor.withValues(alpha: 0.15),
            child: Icon(_getProtocolIcon(), color: primaryColor),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  host.label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  host.protocol.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Text(
            '${host.username != null && host.username!.isNotEmpty ? '${host.username}@' : ''}${host.hostname}:${host.port}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              isConnecting
                  ? const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.green,
                        ),
                      ),
                    )
                  : IconButton(
                      key: Key('connect_host_${host.id}'),
                      icon: const Icon(Icons.play_arrow, color: Colors.green),
                      tooltip: 'Connect Terminal',
                      onPressed: onConnect,
                    ),
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete,
                  size: 20,
                  color: Colors.redAccent,
                ),
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
