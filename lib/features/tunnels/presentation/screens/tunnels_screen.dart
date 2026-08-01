import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/terly_tokens.dart';
import '../../../../app/widgets/terly_ui.dart';
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
        await ref.read(tunnelsProvider.notifier).addRule(rule);
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
        await ref.read(tunnelsProvider.notifier).updateRule(updatedRule);
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
    final state = ref.watch(tunnelsProvider);
    final activeTunnelsAsync = ref.watch(activeTunnelsStreamProvider);
    final filteredRules = widget.filterHostId != null
        ? state.rules.where((r) => r.hostId == widget.filterHostId).toList()
        : state.rules;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          TerlyPageHeader(
            icon: LucideIcons.network,
            title: 'Port Forwarding & Tunnels Matrix',
            description: 'Local, remote and SOCKS5 forwarding rules',
            actions: [
              IconButton(
                icon: const Icon(LucideIcons.refreshCw, size: 17),
                tooltip: 'Refresh Rules',
                onPressed: () => ref
                    .read(tunnelsProvider.notifier)
                    .loadRules(widget.filterHostId),
              ),
              ShadButton(
                size: ShadButtonSize.sm,
                onPressed: _openCreateRuleDialog,
                leading: const Icon(LucideIcons.plus, size: 16),
                child: const Text('Add Tunnel Rule'),
              ),
            ],
          ),
          Expanded(
            child: activeTunnelsAsync.when(
              data: (activeTunnels) {
                final activeMap = {for (var t in activeTunnels) t.ruleId: t};

                if (state.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (filteredRules.isEmpty) {
                  return TerlyEmptyState(
                    icon: LucideIcons.network,
                    title: 'No Port Forwarding Rules configured.',
                    description:
                        'Create a rule to route traffic through an SSH session.',
                    actions: [
                      ShadButton(
                        size: ShadButtonSize.sm,
                        onPressed: _openCreateRuleDialog,
                        child: const Text('Create Your First Rule'),
                      ),
                    ],
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
              error: (err, stack) => TerlyEmptyState(
                icon: LucideIcons.triangleAlert,
                title: 'Tunnels could not be loaded',
                description: '$err',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard({
    required TunnelRuleModel rule,
    ActiveTunnel? activeTunnel,
    HostModel? host,
  }) {
    final tokens = TerlyTokens.resolve(context);
    final isActive = activeTunnel?.isActive ?? false;

    TerlyStatusTone badgeTone;
    String badgeText;

    switch (rule.type) {
      case 'local':
        badgeTone = TerlyStatusTone.info;
        badgeText = 'LOCAL (-L)';
        break;
      case 'remote':
        badgeTone = TerlyStatusTone.neutral;
        badgeText = 'REMOTE (-R)';
        break;
      case 'dynamic':
        badgeTone = TerlyStatusTone.warning;
        badgeText = 'DYNAMIC SOCKS5 (-D)';
        break;
      default:
        badgeTone = TerlyStatusTone.neutral;
        badgeText = rule.type.toUpperCase();
    }

    return TerlySurface(
      borderColor: isActive ? tokens.success.withValues(alpha: 0.55) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TerlyStatusChip(label: badgeText, tone: badgeTone),
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
                  activeThumbColor: tokens.success,
                  onChanged: (value) async {
                    final notifier = ref.read(tunnelsProvider.notifier);
                    if (value) {
                      final activeClient =
                          widget.activeSshClient ??
                          ref
                              .read(terminalTabsProvider)
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
                  icon: const Icon(LucideIcons.ellipsis, size: 18),
                  onSelected: (val) {
                    if (val == 'edit') _openEditRuleDialog(rule);
                    if (val == 'delete') {
                      ref.read(tunnelsProvider.notifier).deleteRule(rule.id);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(LucideIcons.pencil, size: 16),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(LucideIcons.trash2, size: 16),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle()),
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
                color: tokens.canvas,
                borderRadius: BorderRadius.circular(tokens.radiusSmall),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.monitor, size: 17, color: tokens.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    '127.0.0.1:${rule.localPort}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      LucideIcons.arrowRight,
                      size: 16,
                      color: tokens.brand,
                    ),
                  ),
                  if (rule.type == 'dynamic') ...[
                    Icon(LucideIcons.shield, size: 18, color: tokens.warning),
                    const SizedBox(width: 6),
                    Text(
                      'SOCKS5 Dynamic Bridge',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: tokens.warning,
                      ),
                    ),
                  ] else ...[
                    Icon(LucideIcons.server, size: 18, color: tokens.brand),
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
                  Icon(LucideIcons.gauge, size: 16, color: tokens.success),
                  const SizedBox(width: 6),
                  Text(
                    'Speed: ${activeTunnel.formattedSpeed}',
                    style: TextStyle(
                      color: tokens.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    LucideIcons.chartNoAxesColumnIncreasing,
                    size: 16,
                    color: tokens.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Total Transferred: ${activeTunnel.formattedBytes}',
                    style: TextStyle(color: tokens.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ],
            if (activeTunnel?.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Error: ${activeTunnel!.error}',
                  style: TextStyle(color: tokens.danger, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
