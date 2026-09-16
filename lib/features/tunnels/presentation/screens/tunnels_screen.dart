import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/network/tunnel_engine.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/domain/services/host_launcher.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../domain/models/tunnel_rule_model.dart';
import '../providers/tunnels_providers.dart';
import '../widgets/tunnel_form_dialog.dart';

class TunnelsScreen extends ConsumerStatefulWidget {
  final String? filterHostId;

  const TunnelsScreen({super.key, this.filterHostId});

  @override
  ConsumerState<TunnelsScreen> createState() => _TunnelsScreenState();
}

class _TunnelsScreenState extends ConsumerState<TunnelsScreen> {
  final Map<String, HostModel> _hostsMap = {};

  /// Rules whose SSH connection is being dialed right now. A background
  /// connect can take seconds and produces nothing visible until it lands, so
  /// the card shows it rather than looking like a dead button.
  final Set<String> _startingRuleIds = {};

  @override
  void initState() {
    super.initState();
    _loadHostsMap();
  }

  Future<void> _loadHostsMap() async {
    try {
      final hosts = await ref
          .read(hostsRepositoryProvider)
          .getHostsByWorkspace(ref.read(activeWorkspaceIdProvider));
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
    final tokens = ShellVibeTokens.resolve(context);
    final state = ref.watch(tunnelsProvider);
    final activeTunnelsAsync = ref.watch(activeTunnelsStreamProvider);
    final filteredRules = widget.filterHostId != null
        ? state.rules.where((r) => r.hostId == widget.filterHostId).toList()
        : state.rules;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ShellVibePanel(
        gradientExtent: 160,
        child: activeTunnelsAsync.when(
          data: (activeTunnels) {
            final activeMap = {for (var t in activeTunnels) t.ruleId: t};
            final activeCount = filteredRules
                .where((rule) => activeMap[rule.id]?.isActive ?? false)
                .length;
            final errorCount = filteredRules
                .where((rule) => activeMap[rule.id]?.error != null)
                .length;

            return Column(
              children: [
                ShellVibeWorkToolbar(
                  title: 'Tunnels',
                  meta:
                      '${filteredRules.length} forwards · $activeCount active'
                      '${errorCount > 0 ? ' · $errorCount error' : ''}',
                  actions: [
                    ShellVibeIconButton(
                      icon: LucideIcons.refreshCw,
                      tooltip: 'Refresh Rules',
                      onPressed: () => ref
                          .read(tunnelsProvider.notifier)
                          .loadRules(widget.filterHostId),
                    ),
                    ShellVibeButton(
                      icon: LucideIcons.plus,
                      label: 'Add tunnel',
                      onPressed: _openCreateRuleDialog,
                    ),
                  ],
                ),
                if (state.isLoading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (filteredRules.isEmpty)
                  Expanded(
                    child: ShellVibeEmptyState(
                      icon: LucideIcons.network,
                      title: 'No port forwarding rules',
                      description:
                          'Create a rule to route traffic through an SSH '
                          'session.',
                      actions: [
                        ShellVibeButton(
                          icon: LucideIcons.plus,
                          label: 'Create your first rule',
                          onPressed: _openCreateRuleDialog,
                        ),
                      ],
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      itemCount: filteredRules.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final rule = filteredRules[index];
                        return _buildRuleCard(
                          rule: rule,
                          activeTunnel: activeMap[rule.id],
                          host: _hostsMap[rule.hostId],
                        );
                      },
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(14, 0, 14, tokens.panelGap + 4),
                  child: ShellVibeInfoNote(
                    message:
                        'Starting a forward opens its own SSH session when no '
                        'terminal is connected to that host. Tunnels stay open '
                        'after their session closes; they stop when the app '
                        'quits.',
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => ShellVibeEmptyState(
            icon: LucideIcons.triangleAlert,
            title: 'Tunnels could not be loaded',
            description: '$err',
          ),
        ),
      ),
    );
  }

  /// One forwarding rule, laid out as its own card.
  ///
  /// The route reads left to right as `from → to` with the arrow tinted by
  /// state, so the direction of a `-L` and an `-R` rule is visible without
  /// decoding the flag.
  Widget _buildRuleCard({
    required TunnelRuleModel rule,
    ActiveTunnel? activeTunnel,
    HostModel? host,
  }) {
    final tokens = ShellVibeTokens.resolve(context);
    final isActive = activeTunnel?.isActive ?? false;
    final hasError = activeTunnel?.error != null;
    final isStarting = _startingRuleIds.contains(rule.id);
    final isDynamic = rule.type == 'dynamic';

    final accent = hasError
        ? tokens.danger
        : isActive
        ? tokens.brand
        : tokens.textMuted;

    final kindLabel = switch (rule.type) {
      'local' => 'local',
      'remote' => 'remote',
      'dynamic' => 'dynamic socks5',
      _ => rule.type,
    };
    final stateLabel = hasError
        ? 'failed'
        : isActive
        ? 'active'
        : isStarting
        ? 'connecting'
        : 'stopped';
    final detailLabel = hasError
        ? activeTunnel!.error!
        : isActive
        ? '${activeTunnel!.formattedSpeed} · '
              '${activeTunnel.formattedBytes} transferred'
        : isStarting
        ? 'opening an SSH session'
        : 'not running';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: isActive && !hasError
            ? tokens.brand.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: hasError
              ? tokens.danger.withValues(alpha: 0.28)
              : isActive
              ? tokens.brand.withValues(alpha: 0.20)
              : tokens.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(
                alpha: hasError || isActive ? 0.13 : 0.04,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              hasError ? LucideIcons.triangleAlert : LucideIcons.network,
              size: 20,
              color: accent,
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  host?.label ?? 'Host ${rule.hostId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: isActive ? tokens.textPrimary : tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$kindLabel · ${host?.hostname ?? rule.hostId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: shellvibeMono(
                    context,
                    size: 11,
                    color: tokens.textSubtle,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _TunnelRoute(
              from: '127.0.0.1:${rule.localPort}',
              to: isDynamic
                  ? 'socks5 bridge'
                  : '${rule.remoteHost}:${rule.remotePort}',
              accent: accent,
              lit: isActive || hasError,
            ),
          ),
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stateLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detailLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: shellvibeMono(
                    context,
                    size: 11,
                    color: tokens.textSubtle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          if (isStarting)
            const SizedBox(
              width: 34,
              height: 34,
              child: Center(
                child: SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            ShellVibeIconButton(
              icon: hasError
                  ? LucideIcons.refreshCw
                  : isActive
                  ? LucideIcons.square
                  : LucideIcons.play,
              tooltip: isActive ? 'Stop tunnel' : 'Start tunnel',
              ringed: true,
              onPressed: () => unawaited(_toggleRule(rule, start: !isActive)),
            ),
          const SizedBox(width: 7),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            iconSize: 16,
            tooltip: 'Tunnel actions',
            icon: Icon(LucideIcons.ellipsis, size: 16, color: tokens.textMuted),
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
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(LucideIcons.trash2, size: 16, color: tokens.danger),
                    const SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: tokens.danger)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Starts or stops a rule.
  ///
  /// Starting no longer requires a terminal session: the notifier reuses a
  /// connected tab for this host when there is one and otherwise dials in the
  /// background, so the only thing left here is the waiting state and the
  /// prompts — credentials and an unknown host key — that need a widget to
  /// show them in.
  Future<void> _toggleRule(TunnelRuleModel rule, {required bool start}) async {
    final notifier = ref.read(tunnelsProvider.notifier);
    if (!start) {
      await notifier.stopRule(rule.id);
      return;
    }
    if (_startingRuleIds.contains(rule.id)) return;
    setState(() => _startingRuleIds.add(rule.id));
    final launcher = HostLauncher(context: context, ref: ref);
    try {
      await notifier.startRule(
        rule,
        resolveIdentity: launcher.resolveIdentity,
        onHostKeyPrompt: launcher.promptHostKey,
      );
    } catch (e) {
      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast.destructive(
          title: const Text('Tunnel could not start'),
          description: Text('$e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _startingRuleIds.remove(rule.id));
      }
    }
  }
}

/// `from ——→ to`, drawn as two hairlines around a state-tinted arrow.
class _TunnelRoute extends StatelessWidget {
  final String from;
  final String to;
  final Color accent;
  final bool lit;

  const _TunnelRoute({
    required this.from,
    required this.to,
    required this.accent,
    required this.lit,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final lineColor = lit
        ? accent.withValues(alpha: 0.35)
        : tokens.textPrimary.withValues(alpha: 0.08);
    return Row(
      children: [
        Flexible(
          child: Text(
            from,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: shellvibeMono(
              context,
              size: 13,
              color: tokens.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Container(height: 1, color: lineColor)),
        const SizedBox(width: 14),
        Icon(LucideIcons.arrowRight, size: 15, color: accent),
        const SizedBox(width: 14),
        Expanded(child: Container(height: 1, color: lineColor)),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            to,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: shellvibeMono(
              context,
              size: 13,
              color: tokens.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
