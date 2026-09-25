import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/host_group_model.dart';
import '../../domain/models/host_model.dart';
import 'host_list_filter.dart';

/// Inline right-hand detail panel — the wireframe's replacement for a modal.
class HostDetailPanel extends StatelessWidget {
  final HostModel host;
  final List<HostModel> hosts;
  final List<HostGroupModel> groups;
  final bool connected;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onConnect;
  final VoidCallback onOpenSftp;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  const HostDetailPanel({
    super.key,
    required this.host,
    required this.hosts,
    required this.groups,
    required this.connected,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onConnect,
    required this.onOpenSftp,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final jumpHost = hosts
        .where((candidate) => candidate.id == host.jumpHostId)
        .firstOrNull;
    final group = groups
        .where((candidate) => candidate.id == host.groupId)
        .firstOrNull;

    final address =
        '${host.username != null && host.username!.isNotEmpty ? '${host.username}@' : ''}'
        '${host.hostname}:${host.port}';

    return ListView(
      key: const Key('host_detail_drawer'),
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    host.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address,
                    style: shellvibeMono(
                      context,
                      size: 11,
                      color: tokens.textSubtle,
                    ),
                  ),
                ],
              ),
            ),
            // The row's star is revealed by hover, which a phone has none of,
            // so the panel carries the toggle for both.
            ShellVibeIconButton(
              buttonKey: Key('detail_favorite_${host.id}'),
              icon: LucideIcons.star,
              tooltip: isFavorite
                  ? 'Remove from favorites'
                  : 'Add to favorites',
              active: isFavorite,
              onPressed: onToggleFavorite,
            ),
            ShellVibeIconButton(
              icon: LucideIcons.x,
              tooltip: 'Close details',
              onPressed: onClose,
            ),
          ],
        ),
        const SizedBox(height: 14),
        // The state pill carries the uptime as well as the state: on a detail
        // panel the two are read together, and splitting them wastes a row.
        _HostStatePill(connected: connected),
        const SizedBox(height: 14),
        ShellVibeButton(
          buttonKey: const Key('detail_open_terminal'),
          icon: LucideIcons.terminal,
          label: 'Open terminal',
          expand: true,
          onPressed: onConnect,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (hostSupportsFileTransfer(host)) ...[
              Expanded(
                child: ShellVibeButton.secondary(
                  buttonKey: const Key('detail_open_sftp'),
                  label: 'Files',
                  expand: true,
                  onPressed: onOpenSftp,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: ShellVibeButton.secondary(
                label: 'Tunnel',
                expand: true,
                onPressed: () => GoRouter.maybeOf(context)?.go('/tunnels'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ShellVibeButton.secondary(
                label: 'Edit',
                expand: true,
                onPressed: onEdit,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const ShellVibeSectionLabel(
          label: 'Connection',
          padding: EdgeInsets.only(bottom: 8),
        ),
        ShellVibeDetailRow(label: 'protocol', value: host.protocol),
        ShellVibeDetailRow(label: 'port', value: '${host.port}'),
        ShellVibeDetailRow(label: 'user', value: host.username ?? '—'),
        ShellVibeDetailRow(label: 'group', value: group?.name ?? '—'),
        ShellVibeDetailRow(label: 'jump host', value: jumpHost?.label ?? '—'),
        ShellVibeDetailRow(
          label: 'identity',
          value: host.identityId == null ? 'none' : 'from vault',
        ),
        const SizedBox(height: 20),
        ShellVibeButton.danger(
          label: 'Delete host',
          expand: true,
          onPressed: onDelete,
        ),
      ],
    );
  }
}

/// The connection state banner at the top of the host detail panel.
class _HostStatePill extends StatelessWidget {
  final bool connected;

  const _HostStatePill({required this.connected});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final color = connected ? tokens.brand : tokens.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          ShellVibeStatusDot(
            state: connected
                ? ShellVibeDotState.online
                : ShellVibeDotState.idle,
          ),
          const SizedBox(width: 8),
          Text(
            connected ? 'connected' : 'not connected',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: connected ? tokens.brandSoft : tokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
