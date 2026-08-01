import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/network/tunnel_engine.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../domain/models/tunnel_rule_model.dart';
import '../providers/tunnels_providers.dart';
import '../widgets/tunnel_form_dialog.dart';

class TunnelsScreen extends ConsumerStatefulWidget {
  final SSHClient? activeSshClient;
  final String? filterHostId;

  const TunnelsScreen({super.key, this.activeSshClient, this.filterHostId});

  @override
  ConsumerState<TunnelsScreen> createState() => _TunnelsScreenState();
}

class _TunnelsScreenState extends ConsumerState<TunnelsScreen> {
  final Map<String, HostModel> _hostsMap = {};

  @override
  void initState() {
    super.initState();
    _loadHostsMap();
  }

  Future<void> _loadHostsMap() async {
    try {
      final hosts = await ref.read(hostsRepositoryProvider).getAllHosts();
      if (mounted) {
        setState(() {
          for (final h in hosts) {
            _hostsMap[h.id] = h;
          }
        });
      }
    } catch (_) {}
  }

  void _openCreateRuleDialog() async {
    final rule = await showDialog<TunnelRuleModel>(
      context: context,
      builder: (_) => TunnelFormDialog(defaultHostId: widget.filterHostId),
    );

    if (rule != null) {
      try {
        await ref.read(tunnelsNotifierProvider.notifier).addRule(rule);
      } catch (e) {
        if (mounted) {
          ShadToaster.of(context).show(
            ShadToast.destructive(
              title: const Text('Save Tunnel Error'),
              description: Text('$e'),
            ),
          );
        }
      }
    }
  }

  void _openEditRuleDialog(TunnelRuleModel rule) async {
    final updatedRule = await showDialog<TunnelRuleModel>(
      context: context,
      builder: (_) => TunnelFormDialog(rule: rule, defaultHostId: rule.hostId),
    );

    if (updatedRule != null) {
      try {
        await ref
            .read(tunnelsNotifierProvider.notifier)
            .updateRule(updatedRule);
      } catch (e) {
        if (mounted) {
          ShadToaster.of(context).show(
            ShadToast.destructive(
              title: const Text('Save Tunnel Error'),
              description: Text('$e'),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tunnelsNotifierProvider);
    final activeTunnelsAsync = ref.watch(activeTunnelsStreamProvider);
    final colorScheme = ShadTheme.of(context).colorScheme;

    final filteredRules = widget.filterHostId != null
        ? state.rules.where((r) => r.hostId == widget.filterHostId).toList()
        : state.rules;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: colorScheme.card,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.hub, color: Colors.cyanAccent),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'Port Forwarding & Tunnels Matrix',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Rules',
            onPressed: () => ref
                .read(tunnelsNotifierProvider.notifier)
                .loadRules(widget.filterHostId),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.cyanAccent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Add Tunnel Rule'),
        onPressed: _openCreateRuleDialog,
      ),
      body: activeTunnelsAsync.when(
        data: (activeTunnels) {
          final activeMap = {for (var t in activeTunnels) t.ruleId: t};

          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (filteredRules.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.hub_outlined,
                    size: 64,
                    color: colorScheme.mutedForeground,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Port Forwarding Rules configured.',
                    style: TextStyle(
                      color: colorScheme.mutedForeground,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Create Your First Rule'),
                    onPressed: _openCreateRuleDialog,
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: filteredRules.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final rule = filteredRules[index];
              final activeTunnel = activeMap[rule.id];
              final host = _hostsMap[rule.hostId];

              return _buildRuleCard(
                rule: rule,
                activeTunnel: activeTunnel,
                host: host,
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) =>
            Center(child: Text('Error loading tunnels: $err')),
      ),
    );
  }

  Widget _buildRuleCard({
    required TunnelRuleModel rule,
    ActiveTunnel? activeTunnel,
    HostModel? host,
  }) {
    final colorScheme = ShadTheme.of(context).colorScheme;
    final isActive = activeTunnel?.isActive ?? false;

    Color badgeColor;
    String badgeText;

    switch (rule.type) {
      case 'local':
        badgeColor = Colors.cyan;
        badgeText = 'LOCAL (-L)';
        break;
      case 'remote':
        badgeColor = Colors.purpleAccent;
        badgeText = 'REMOTE (-R)';
        break;
      case 'dynamic':
        badgeColor = Colors.orangeAccent;
        badgeText = 'DYNAMIC SOCKS5 (-D)';
        break;
      default:
        badgeColor = Colors.blueGrey;
        badgeText = rule.type.toUpperCase();
    }

    return Card(
      color: colorScheme.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive ? Colors.greenAccent : colorScheme.border,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: badgeColor, width: 1),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: badgeColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    host != null
                        ? '${host.label} (${host.hostname})'
                        : 'Host ID: ${rule.hostId}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Switch(
                  value: isActive,
                  activeThumbColor: Colors.greenAccent,
                  onChanged: (value) async {
                    final notifier = ref.read(tunnelsNotifierProvider.notifier);
                    if (value) {
                      final activeClient =
                          widget.activeSshClient ??
                          ref
                              .read(terminalTabsNotifierProvider)
                              .activeTab
                              ?.sshSessionManager
                              ?.client;
                      if (activeClient != null && !activeClient.isClosed) {
                        await notifier.startRule(rule, activeClient);
                      } else {
                        ShadToaster.of(context).show(
                          const ShadToast.destructive(
                            description: Text(
                              'Active SSH Connection required to start tunnel',
                            ),
                          ),
                        );
                      }
                    } else {
                      await notifier.stopRule(rule.id);
                    }
                  },
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (val) {
                    if (val == 'edit') _openEditRuleDialog(rule);
                    if (val == 'delete') {
                      ref
                          .read(tunnelsNotifierProvider.notifier)
                          .deleteRule(rule.id);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 16),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.redAccent, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Delete',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Rule Flow Diagram / Route text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.muted,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.computer, size: 18, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    '127.0.0.1:${rule.localPort}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: Colors.cyanAccent,
                    ),
                  ),
                  if (rule.type == 'dynamic') ...[
                    const Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: Colors.orangeAccent,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'SOCKS5 Dynamic Bridge',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.orangeAccent,
                      ),
                    ),
                  ] else ...[
                    const Icon(
                      Icons.dns_outlined,
                      size: 18,
                      color: Colors.cyanAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${rule.remoteHost}:${rule.remotePort}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isActive && activeTunnel != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.speed, size: 16, color: Colors.greenAccent),
                  const SizedBox(width: 6),
                  Text(
                    'Speed: ${activeTunnel.formattedSpeed}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.data_usage,
                    size: 16,
                    color: colorScheme.mutedForeground,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Total Transferred: ${activeTunnel.formattedBytes}',
                    style: TextStyle(
                      color: colorScheme.mutedForeground,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
            if (activeTunnel?.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Error: ${activeTunnel!.error}',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
