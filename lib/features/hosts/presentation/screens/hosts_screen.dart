import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dialogs/host_form_dialog.dart';
import '../dialogs/host_group_form_dialog.dart';
import '../notifiers/host_groups_notifier.dart';
import '../notifiers/hosts_notifier.dart';
import '../../domain/models/host_group_model.dart';
import '../../domain/models/host_model.dart';

class HostsScreen extends ConsumerStatefulWidget {
  final void Function(HostModel host)? onConnectHost;

  const HostsScreen({
    super.key,
    this.onConnectHost,
  });

  @override
  ConsumerState<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends ConsumerState<HostsScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final hostsAsync = ref.watch(hostsNotifierProvider);
    final groupsAsync = ref.watch(hostGroupsNotifierProvider);

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
                return groupsAsync.when(
                  data: (groups) {
                    final filteredHosts = hosts.where((h) {
                      final label = h.label.toLowerCase();
                      final host = h.hostname.toLowerCase();
                      final proto = h.protocol.toLowerCase();
                      return label.contains(_searchQuery) ||
                          host.contains(_searchQuery) ||
                          proto.contains(_searchQuery);
                    }).toList();

                    if (filteredHosts.isEmpty && groups.isEmpty) {
                      return const Center(
                        child: Text('No hosts or groups configured.'),
                      );
                    }

                    // Organize hosts into groups
                    final ungroupedHosts =
                        filteredHosts.where((h) => h.groupId == null).toList();

                    return ListView(
                      children: [
                        // Display Groups
                        ...groups.map(
                          (group) {
                            final groupHosts = filteredHosts
                                .where((h) => h.groupId == group.id)
                                .toList();
                            return _GroupExpansionTile(
                              group: group,
                              hosts: groupHosts,
                              onEditGroup: () =>
                                  _openGroupForm(context, initialGroup: group),
                              onDeleteGroup: () =>
                                  _deleteGroup(context, group),
                              onEditHost: (h) =>
                                  _openHostForm(context, initialHost: h),
                              onDeleteHost: (h) =>
                                  _deleteHost(context, h),
                              onConnectHost: widget.onConnectHost,
                            );
                          },
                        ),
                        // Display Ungrouped Hosts Header if groups exist
                        if (groups.isNotEmpty && ungroupedHosts.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: Text(
                              'Ungrouped Hosts',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ...ungroupedHosts.map(
                          (h) => _HostTile(
                            key: ValueKey(h.id),
                            host: h,
                            onEdit: () =>
                                _openHostForm(context, initialHost: h),
                            onDelete: () => _deleteHost(context, h),
                            onConnect: () => widget.onConnectHost?.call(h),
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, s) => Center(child: Text('Error loading groups: $e')),
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
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Host'),
        content: Text('Are you sure you want to delete "${host.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref.read(hostsNotifierProvider.notifier).deleteHost(host.id);
    }
  }

  Future<void> _deleteGroup(BuildContext context, HostGroupModel group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text('Are you sure you want to delete group "${group.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref.read(hostGroupsNotifierProvider.notifier).deleteGroup(group.id);
    }
  }
}

class _GroupExpansionTile extends StatelessWidget {
  final HostGroupModel group;
  final List<HostModel> hosts;
  final VoidCallback onEditGroup;
  final VoidCallback onDeleteGroup;
  final void Function(HostModel) onEditHost;
  final void Function(HostModel) onDeleteHost;
  final void Function(HostModel)? onConnectHost;

  const _GroupExpansionTile({
    required this.group,
    required this.hosts,
    required this.onEditGroup,
    required this.onDeleteGroup,
    required this.onEditHost,
    required this.onDeleteHost,
    this.onConnectHost,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        leading: Icon(Icons.folder, color: Colors.amber.shade700),
        title: Text(
          group.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${hosts.length} hosts'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: onEditGroup,
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
              onPressed: onDeleteGroup,
            ),
          ],
        ),
        children: hosts
            .map(
              (h) => _HostTile(
                key: ValueKey(h.id),
                host: h,
                onEdit: () => onEditHost(h),
                onDelete: () => onDeleteHost(h),
                onConnect: () => onConnectHost?.call(h),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _HostTile extends StatelessWidget {
  final HostModel host;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onConnect;

  const _HostTile({
    super.key,
    required this.host,
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withValues(alpha: 0.15),
          child: Icon(_getProtocolIcon(), color: Colors.blue),
        ),
        title: Row(
          children: [
            Text(
              host.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                host.protocol.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text('${host.hostname}:${host.port}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
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
              icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent),
              tooltip: 'Delete',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
