import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/mcp_enums.dart';
import '../notifiers/mcp_activity_notifier.dart';
import '../notifiers/mcp_settings_notifier.dart';
import '../screens/mcp_audit_screen.dart';

/// The product's answer to "the agent is a black box": a live feed of every
/// connected AI client, every command it just ran (and how the policy engine
/// decided it), what it currently holds, and one destructive-styled button
/// that cuts all of it off.
///
/// Every color and shape here is pulled from [ShellVibeTokens] and the shared
/// [ShellVibeStatusChip]/[ShellVibeQuietButton] widgets — nothing invented for
/// this one panel — so it reads as part of the app rather than a bolted-on
/// security console.
class McpActivityPanel extends ConsumerWidget {
  const McpActivityPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    final activityAsync = ref.watch(mcpActivityProvider);

    return ShellVibePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.radioTower, size: 16, color: tokens.brand),
              const SizedBox(width: 8),
              Text(
                'AI Activity',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
              const Spacer(),
              const _AuditLogLink(),
            ],
          ),
          const SizedBox(height: 14),
          activityAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.circleAlert, size: 16, color: tokens.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Could not load AI activity: $error',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: tokens.danger),
                    ),
                  ),
                ],
              ),
            ),
            data: (state) {
              if (state.clients.isEmpty) {
                return const ShellVibeInfoNote(
                  icon: LucideIcons.radioTower,
                  message:
                      'No AI client is connected right now. Once an agent '
                      'opens a session, every command it runs appears here '
                      'live.',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final activity in state.clients) ...[
                    _ClientActivityBlock(activity: activity),
                    const SizedBox(height: 14),
                  ],
                ],
              );
            },
          ),
          Divider(height: 24, color: tokens.border),
          const _PanicAction(),
        ],
      ),
    );
  }
}

class _AuditLogLink extends StatelessWidget {
  const _AuditLogLink();

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return InkWell(
      key: const Key('mcp_activity_open_audit_log'),
      borderRadius: BorderRadius.circular(tokens.radiusSmall),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const McpAuditScreen())),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Full log',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tokens.brand,
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronRight, size: 13, color: tokens.brand),
          ],
        ),
      ),
    );
  }
}

/// One connected client's header, live timeline, and its two manageable
/// lists (active grants, remembered approvals). Expand/collapse state is
/// purely local UI state — nothing here changes what is actually granted.
class _ClientActivityBlock extends StatefulWidget {
  final McpClientActivity activity;

  const _ClientActivityBlock({required this.activity});

  @override
  State<_ClientActivityBlock> createState() => _ClientActivityBlockState();
}

class _ClientActivityBlockState extends State<_ClientActivityBlock> {
  bool _grantsExpanded = false;
  bool _approvalsExpanded = false;

  static const int _maxTimelineRows = 6;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final activity = widget.activity;
    final timeline = activity.timeline.take(_maxTimelineRows).toList();
    final hostCount = activity.grantedHostCount;
    final sessionCount = activity.sessions.length;

    return ShellVibeSurface(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const ShellVibeStatusDot(state: ShellVibeDotState.online),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  activity.client.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'connected · $hostCount ${hostCount == 1 ? 'host' : 'hosts'} · '
                  '$sessionCount active '
                  '${sessionCount == 1 ? 'session' : 'sessions'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: shellvibeMono(
                    context,
                    size: 11,
                    color: tokens.textSubtle,
                  ),
                ),
              ),
            ],
          ),
          if (timeline.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final row in timeline) _TimelineRowTile(row: row),
          ],
          const SizedBox(height: 10),
          Divider(height: 1, color: tokens.border),
          const SizedBox(height: 8),
          _ManageRow(
            rowKey: Key('mcp_activity_grants_toggle_${activity.client.id}'),
            label: 'Active grants (${activity.activeGrants.length})',
            expanded: _grantsExpanded,
            onToggle: activity.activeGrants.isEmpty
                ? null
                : () => setState(() => _grantsExpanded = !_grantsExpanded),
          ),
          if (_grantsExpanded) _GrantsManageList(activity: activity),
          const SizedBox(height: 4),
          _ManageRow(
            rowKey: Key('mcp_activity_approvals_toggle_${activity.client.id}'),
            label:
                'Remembered approvals (${activity.rememberedApprovals.length})',
            expanded: _approvalsExpanded,
            onToggle: activity.rememberedApprovals.isEmpty
                ? null
                : () =>
                      setState(() => _approvalsExpanded = !_approvalsExpanded),
          ),
          if (_approvalsExpanded) _ApprovalsManageList(activity: activity),
        ],
      ),
    );
  }
}

class _ManageRow extends StatelessWidget {
  final Key rowKey;
  final String label;
  final bool expanded;
  final VoidCallback? onToggle;

  const _ManageRow({
    required this.rowKey,
    required this.label,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
          ),
        ),
        ShellVibeButton.secondary(
          buttonKey: rowKey,
          icon: expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
          label: expanded ? 'Hide' : 'Manage',
          onPressed: onToggle,
        ),
      ],
    );
  }
}

class _GrantsManageList extends ConsumerWidget {
  final McpClientActivity activity;

  const _GrantsManageList({required this.activity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Column(
        children: [
          for (final grant in activity.activeGrants)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      activity.hostLabelFor(grant.hostId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: shellvibeMono(
                        context,
                        size: 12,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ShellVibeStatusChip(
                    label: McpAccessMode.fromName(grant.mode).name,
                    tone: ShellVibeStatusTone.brand,
                  ),
                  const SizedBox(width: 8),
                  ShellVibeIconButton(
                    key: Key(
                      'mcp_activity_revoke_grant_${activity.client.id}_${grant.hostId}',
                    ),
                    icon: LucideIcons.x,
                    tooltip: 'Revoke access',
                    onPressed: () => ref
                        .read(mcpActivityProvider.notifier)
                        .revokeGrant(
                          clientId: activity.client.id,
                          hostId: grant.hostId,
                        ),
                    danger: true,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ApprovalsManageList extends ConsumerWidget {
  final McpClientActivity activity;

  const _ApprovalsManageList({required this.activity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Column(
        children: [
          for (final approval in activity.rememberedApprovals)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activity.hostLabelFor(approval.hostId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: shellvibeMono(
                            context,
                            size: 11,
                            color: tokens.textSubtle,
                          ),
                        ),
                        Text(
                          approval.commandNormalized,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: shellvibeMono(
                            context,
                            size: 12,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    approval.expiresAt == null
                        ? 'no expiry'
                        : 'until ${_formatClock(approval.expiresAt!)}',
                    style: shellvibeMono(
                      context,
                      size: 11,
                      color: tokens.textSubtle,
                    ),
                  ),
                  ShellVibeIconButton(
                    key: Key('mcp_activity_revoke_approval_${approval.id}'),
                    icon: LucideIcons.x,
                    tooltip: 'Forget this approval',
                    onPressed: () => ref
                        .read(mcpActivityProvider.notifier)
                        .revokeApproval(approval.id),
                    danger: true,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineRowTile extends StatelessWidget {
  final McpActivityRow row;

  const _TimelineRowTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final (time, hostLabel, tool, detail, status) = switch (row) {
      McpActivityAuditRow(:final entry) => (
        entry.at,
        entry.hostLabel ?? '—',
        entry.tool,
        summarizeMcpAuditArgs(entry.argsJson),
        mcpAuditRowStatusForWire(entry.decision),
      ),
      McpActivityPendingRow(:final pending) => (
        pending.requestedAt,
        pending.request.hostLabel,
        'run_command',
        pending.request.command,
        McpAuditRowStatus.pending,
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              _formatClock(time),
              style: shellvibeMono(context, size: 11, color: tokens.textSubtle),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              hostLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: shellvibeMono(
                context,
                size: 11,
                color: tokens.textSecondary,
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              tool,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: shellvibeMono(
                context,
                size: 11,
                color: tokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: shellvibeMono(context, size: 11, color: tokens.textMuted),
            ),
          ),
          const SizedBox(width: 6),
          McpDecisionChip(status: status),
        ],
      ),
    );
  }
}

/// The kill switch. No confirmation dialog — a panic button that hesitates
/// isn't one. It calls straight through to [McpSettingsNotifier.panic],
/// which is the single implementation of "cut everything" in this codebase;
/// this panel does not re-close sessions or re-revoke grants itself.
class _PanicAction extends ConsumerWidget {
  const _PanicAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ShellVibeButton.danger(
      key: const Key('mcp_activity_panic_button'),
      label: 'CUT ALL AGENT ACCESS',
      icon: LucideIcons.power,
      onPressed: () => ref.read(mcpSettingsProvider.notifier).panic(),
      expand: true,
    );
  }
}

String _formatClock(DateTime at) {
  final local = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

/// What one timeline row visually communicates. [pending] has no
/// [AuditDecision] counterpart — it is a live wait, not yet a decision.
enum McpAuditRowStatus {
  allowed,
  confirmed,
  denied,
  autoDenied,
  error,
  pending,
}

/// Maps [McpAuditLogData.decision] — stored as [AuditDecision.wireName], not
/// as the enum itself — back to a [McpAuditRowStatus]. Takes the wire string
/// directly rather than an [AuditDecision] because that is exactly what the
/// drift row carries; [AuditDecision] itself exposes no reverse `fromName`
/// (only [RiskCategory] and friends need one, for values a client sends in),
/// so this is the one place that string is ever interpreted.
McpAuditRowStatus mcpAuditRowStatusForWire(String decisionWireName) =>
    switch (decisionWireName) {
      'allowed' => McpAuditRowStatus.allowed,
      'confirmed' => McpAuditRowStatus.confirmed,
      'denied' => McpAuditRowStatus.denied,
      'auto_denied' => McpAuditRowStatus.autoDenied,
      // An unrecognized value must never read as a quiet success.
      _ => McpAuditRowStatus.error,
    };

/// The one place a decision (or a still-pending wait) is turned into a
/// color and an icon, shared by the panel and the full audit screen so the
/// two surfaces never drift into disagreeing visual languages.
class McpDecisionChip extends StatelessWidget {
  final McpAuditRowStatus status;

  const McpDecisionChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (icon, label, tone) = switch (status) {
      McpAuditRowStatus.allowed => (
        LucideIcons.check,
        'allow',
        ShellVibeStatusTone.success,
      ),
      McpAuditRowStatus.confirmed => (
        LucideIcons.checkCheck,
        'confirmed',
        ShellVibeStatusTone.success,
      ),
      McpAuditRowStatus.denied => (
        LucideIcons.x,
        'denied',
        ShellVibeStatusTone.danger,
      ),
      McpAuditRowStatus.autoDenied => (
        LucideIcons.ban,
        'auto-denied',
        ShellVibeStatusTone.danger,
      ),
      McpAuditRowStatus.error => (
        LucideIcons.triangleAlert,
        'error',
        ShellVibeStatusTone.warning,
      ),
      McpAuditRowStatus.pending => (
        LucideIcons.pause,
        'awaiting approval',
        ShellVibeStatusTone.warning,
      ),
    };
    return ShellVibeStatusChip(label: label, icon: icon, tone: tone);
  }
}
