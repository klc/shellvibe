import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/terly_tokens.dart';
import '../../../../app/widgets/terly_ui.dart';
import '../../../terminal/presentation/dialogs/host_key_prompt_dialog.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../../../shared/providers/workspace_provider.dart';
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
    final tokens = TerlyTokens.resolve(context);

    return Scaffold(
      body: Column(
        children: [
          TerlyPageHeader(
            icon: LucideIcons.server,
            title: 'Hosts & Servers',
            description: 'Connect to infrastructure without losing context.',
            actions: [
              IconButton(
                key: const Key('add_group_button'),
                icon: const Icon(LucideIcons.folderPlus, size: 17),
                tooltip: 'Add Group',
                onPressed: () => _openGroupForm(context),
              ),
              ShadButton(
                key: const Key('add_host_button'),
                size: ShadButtonSize.sm,
                leading: const Icon(LucideIcons.plus, size: 16),
                onPressed: () => _openHostForm(context),
                child: const Text('Add Host'),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.pagePadding,
              14,
              tokens.pagePadding,
              10,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TerlySearchField(
                    fieldKey: const Key('hosts_search_input'),
                    hintText: 'Search hosts, addresses and protocols…',
                    onChanged: (value) =>
                        setState(() => _searchQuery = value.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 10),
                groupsAsync.maybeWhen(
                  data: (groups) => TerlyStatusChip(
                    label: '${groups.length} groups',
                    icon: LucideIcons.folders,
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.pagePadding),
            child: Divider(color: tokens.border),
          ),
          Expanded(
            child: hostsAsync.when(
              data: (hosts) {
                final filtered = hosts.where((host) {
                  return host.label.toLowerCase().contains(_searchQuery) ||
                      host.hostname.toLowerCase().contains(_searchQuery) ||
                      (host.username ?? '').toLowerCase().contains(
                        _searchQuery,
                      ) ||
                      host.protocol.toLowerCase().contains(_searchQuery);
                }).toList();

                return groupsAsync.when(
                  data: (groups) {
                    if (hosts.isEmpty && groups.isEmpty) {
                      return TerlyEmptyState(
                        icon: LucideIcons.server,
                        title: 'No hosts or groups configured.',
                        description:
                            'Add your first server to connect in one click. You can organize infrastructure into groups at any time.',
                        actions: [
                          ShadButton(
                            onPressed: () => _openHostForm(context),
                            leading: const Icon(LucideIcons.plus, size: 16),
                            child: const Text('Add your first host'),
                          ),
                          ShadButton.outline(
                            onPressed: () => _openGroupForm(context),
                            leading: const Icon(
                              LucideIcons.folderPlus,
                              size: 16,
                            ),
                            child: const Text('Create group'),
                          ),
                        ],
                      );
                    }

                    final categorized = _buildCategorizedItems(
                      filtered,
                      groups,
                      includeEmptyGroups: _searchQuery.isEmpty,
                    );
                    final items = categorized.items;

                    if (items.isEmpty) {
                      return const TerlyEmptyState(
                        icon: LucideIcons.searchX,
                        title: 'No hosts match your search.',
                        description:
                            'Try a label, hostname, username or protocol.',
                      );
                    }

                    return ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        tokens.pagePadding,
                        4,
                        tokens.pagePadding,
                        20,
                      ),
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
                            onEditHost: (host) =>
                                _openHostForm(context, initialHost: host),
                            onDeleteHost: (host) => _deleteHost(context, host),
                            onConnectHost: _onConnectHost,
                            onEditGroup: (group) =>
                                _openGroupForm(context, initialGroup: group),
                            onDeleteGroup: (group) =>
                                _deleteGroup(context, group),
                            connectingHostIds: _connectingHostIds,
                          );
                        }
                        if (item is HostModel) {
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
                  error: (error, stackTrace) => TerlyEmptyState(
                    icon: LucideIcons.triangleAlert,
                    title: 'Could not load host groups',
                    description: '$error',
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => TerlyEmptyState(
                icon: LucideIcons.triangleAlert,
                title: 'Could not load hosts',
                description: '$error',
              ),
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

    await ref
        .read(terminalTabsProvider.notifier)
        .openTabForHost(
          host,
          identity: identity,
          onHostKeyPrompt:
              (hostname, port, keyType, fingerprint, status) async {
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
      builder: (ctx) => HostFormDialog(
        initialHost: initialHost,
        workspaceId: ref.read(activeWorkspaceIdProvider),
      ),
    );
  }

  void _openGroupForm(BuildContext context, {HostGroupModel? initialGroup}) {
    showDialog(
      context: context,
      builder: (ctx) => HostGroupFormDialog(
        initialGroup: initialGroup,
        workspaceId: ref.read(activeWorkspaceIdProvider),
      ),
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

  ({List<Object> items, Map<String, List<HostModel>> groupedHosts})
  _buildCategorizedItems(
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
    final tokens = TerlyTokens.resolve(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TerlySurface(
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(LucideIcons.folder, size: 18, color: tokens.brand),
          title: Text(
            group.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${hosts.length} ${hosts.length == 1 ? 'server' : 'servers'}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(LucideIcons.pencil, size: 16),
                tooltip: 'Edit group',
                onPressed: () => onEditGroup(group),
              ),
              IconButton(
                icon: Icon(LucideIcons.trash2, size: 16, color: tokens.danger),
                tooltip: 'Delete group',
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
        return LucideIcons.terminal;
      case 'mosh':
        return LucideIcons.radioTower;
      case 'local':
        return LucideIcons.monitor;
      case 'serial':
        return LucideIcons.usb;
      default:
        return LucideIcons.server;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        button: onConnect != null,
        label: '${host.label}, ${host.protocol} host at ${host.hostname}',
        child: TerlySurface(
          child: ListTile(
            minTileHeight: 62,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 3,
            ),
            leading: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tokens.brand.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(tokens.radiusMedium),
                border: Border.all(color: tokens.brand.withValues(alpha: 0.20)),
              ),
              child: Icon(_getProtocolIcon(), size: 17, color: tokens.brand),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    host.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                TerlyStatusChip(
                  label: host.protocol.toUpperCase(),
                  tone: TerlyStatusTone.brand,
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        key: Key('connect_host_${host.id}'),
                        icon: Icon(
                          LucideIcons.play,
                          size: 17,
                          color: tokens.success,
                        ),
                        tooltip: 'Connect Terminal',
                        onPressed: onConnect,
                      ),
                PopupMenuButton<String>(
                  tooltip: 'Host actions',
                  icon: const Icon(LucideIcons.ellipsis, size: 17),
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(LucideIcons.pencil, size: 16),
                          SizedBox(width: 8),
                          Text('Edit host'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.trash2,
                            size: 16,
                            color: tokens.danger,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Delete host',
                            style: TextStyle(color: tokens.danger),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
