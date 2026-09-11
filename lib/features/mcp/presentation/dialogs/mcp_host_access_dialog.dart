import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/mcp_enums.dart';
import '../../domain/models/mcp_models.dart';

/// How long a batch of host grants should last before the agent has to ask
/// again.
///
/// This is a UI-only concept — [ApprovalScope] is the equivalent idea for a
/// single remembered command — kept separate because host grants and command
/// approvals are stored in different places and are not required to share a
/// vocabulary.
enum HostAccessDuration {
  once,
  fifteenMinutes,
  session,
  always;

  String get label => switch (this) {
    HostAccessDuration.once => 'Once',
    HostAccessDuration.fifteenMinutes => '15 minutes',
    HostAccessDuration.session => 'This session',
    HostAccessDuration.always => 'Always',
  };

  /// The [HostAccessGrant.expiresAt] this choice implies, anchored at [now].
  ///
  /// `session` and `always` both come back `null` here: neither has a clock
  /// deadline, and the caller is the one that knows which of "good until the
  /// app closes" and "good forever" it is, by the scope it stores the grant
  /// under — this dialog has no such storage to consult, so it hands both
  /// cases back the same "no expiry" signal and leaves the distinction to
  /// whoever persists the grant.
  DateTime? expiresAt(DateTime now) => switch (this) {
    // "Once" has no single-use flag to carry in HostAccessGrant — the model
    // only has a mode and an optional expiry — so the closest honest stand-in
    // is a short window that comfortably covers the agent's very next call
    // and nothing beyond it.
    HostAccessDuration.once => now.add(const Duration(minutes: 2)),
    HostAccessDuration.fifteenMinutes => now.add(const Duration(minutes: 15)),
    HostAccessDuration.session => null,
    HostAccessDuration.always => null,
  };
}

/// What [McpHostAccessDialog] hands back: the answer for
/// [ApprovalCoordinator.resolveHostAccess], plus whether the user also asked
/// to suspend the client that made the request.
///
/// Suspension is carried out of band from [result] because revoking a client
/// is not something [HostAccessResult] has a slot for — it is a fact about
/// the client, not about any one host — so the caller (the widget that owns
/// a [BuildContext] and a repository, not this dialog) is expected to act on
/// [suspendClient] itself.
class HostAccessDialogOutcome {
  final HostAccessResult result;
  final bool suspendClient;

  const HostAccessDialogOutcome({
    required this.result,
    this.suspendClient = false,
  });
}

/// Batch approval window for `request_host_access`.
///
/// Partial approval is the normal case, not an edge case: every row carries
/// its own checkbox and its own mode dropdown, so the user can grant
/// `prod-web-01` at `readonly` while refusing `prod-db-01` outright, in one
/// pass. See docs/mcp_plan.md "Erişim onayı akışı".
///
/// Every way of leaving this dialog other than pressing one of the three
/// action buttons — the barrier (blocked), Escape, a back gesture, an
/// in-flight countdown reaching zero — resolves as a full denial. There is no
/// path out of this widget that grants access without an explicit tap on
/// "Approve".
class McpHostAccessDialog extends StatefulWidget {
  final HostAccessRequest request;

  /// Wall-clock deadline this prompt fails closed at, mirrored from
  /// [PendingHostAccessApproval.expiresAt] so the on-screen countdown agrees
  /// with the coordinator's own timer to the second.
  final DateTime expiresAt;

  const McpHostAccessDialog({
    super.key,
    required this.request,
    required this.expiresAt,
  });

  static Future<HostAccessDialogOutcome?> show(
    BuildContext context, {
    required HostAccessRequest request,
    required DateTime expiresAt,
  }) {
    return showDialog<HostAccessDialogOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          McpHostAccessDialog(request: request, expiresAt: expiresAt),
    );
  }

  @override
  State<McpHostAccessDialog> createState() => _McpHostAccessDialogState();
}

class _McpHostAccessDialogState extends State<McpHostAccessDialog> {
  late final Map<String, bool> _granted;
  late final Map<String, McpAccessMode> _modes;
  HostAccessDuration _duration = HostAccessDuration.session;
  late Timer _ticker;
  late Duration _remaining;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    // Pre-checked: the agent asked for these hosts and each row starts at
    // the host's own safe default mode, so accepting the defaults outright
    // is a reasonable action — the user's job is to narrow, not to build the
    // grant from nothing.
    _granted = {for (final c in widget.request.candidates) c.hostId: true};
    _modes = {
      for (final c in widget.request.candidates) c.hostId: c.suggestedMode,
    };
    _remaining = widget.expiresAt.difference(DateTime.now().toUtc());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  void _tick() {
    final remaining = widget.expiresAt.difference(DateTime.now().toUtc());
    if (remaining.isNegative || remaining == Duration.zero) {
      _ticker.cancel();
      // The coordinator's own timer is racing this one and will resolve the
      // same way; closing here just means the user is not left staring at a
      // prompt that has already failed closed underneath them.
      _closeAsDenied(suspendClient: false);
      return;
    }
    if (mounted) setState(() => _remaining = remaining);
  }

  HostAccessResult _allDenied(String reason) => HostAccessResult(
    granted: const [],
    denied: widget.request.candidates
        .map((c) => HostAccessDenial(hostId: c.hostId, reason: reason))
        .toList(),
  );

  void _closeAsDenied({required bool suspendClient}) {
    if (_resolved || !mounted) return;
    _resolved = true;
    Navigator.of(context).pop(
      HostAccessDialogOutcome(
        result: _allDenied('user_denied'),
        suspendClient: suspendClient,
      ),
    );
  }

  void _approve() {
    if (_resolved) return;
    _resolved = true;
    final now = DateTime.now().toUtc();
    final expiresAt = _duration.expiresAt(now);
    final granted = <HostAccessGrant>[];
    final denied = <HostAccessDenial>[];
    for (final candidate in widget.request.candidates) {
      if (_granted[candidate.hostId] ?? false) {
        granted.add(
          HostAccessGrant(
            hostId: candidate.hostId,
            mode: _modes[candidate.hostId] ?? candidate.suggestedMode,
            expiresAt: expiresAt,
          ),
        );
      } else {
        denied.add(
          HostAccessDenial(hostId: candidate.hostId, reason: 'user_denied'),
        );
      }
    }
    Navigator.of(context).pop(
      HostAccessDialogOutcome(
        result: HostAccessResult(granted: granted, denied: denied),
      ),
    );
  }

  String _formatRemaining(Duration d) {
    final clamped = d.isNegative ? Duration.zero : d;
    final m = clamped.inMinutes;
    final s = clamped.inSeconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final request = widget.request;

    return PopScope(
      // Every non-approval way out — Escape, a back gesture, anything short
      // of pressing "Approve" — must be a refusal, so the pop is intercepted
      // and rerouted through the same deny-all path the "Deny" button uses.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closeAsDenied(suspendClient: false);
      },
      child: ShadDialog(
        constraints: const BoxConstraints(maxWidth: 560),
        title: Text(
          '${request.clientName} wants to connect to '
          '${request.candidates.length} '
          '${request.candidates.length == 1 ? 'server' : 'servers'}',
        ),
        description: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Reason: ${request.reason}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
          ),
        ),
        actions: adaptiveDialogActions(context, [
          ShellVibeButton.secondary(
            key: const Key('mcp_host_access_deny_button'),
            label: 'Deny',
            onPressed: () => _closeAsDenied(suspendClient: false),
          ),
          ShellVibeButton.danger(
            key: const Key('mcp_host_access_deny_suspend_button'),
            label: 'Deny and suspend client',
            onPressed: () => _closeAsDenied(suspendClient: true),
          ),
          ShellVibeButton(
            key: const Key('mcp_host_access_approve_button'),
            label: 'Approve',
            onPressed: _approve,
          ),
        ]),
        actionsAxis: adaptiveDialogActionsAxis(context),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final candidate in request.candidates)
                        _HostRow(
                          candidate: candidate,
                          checked: _granted[candidate.hostId] ?? false,
                          mode:
                              _modes[candidate.hostId] ??
                              candidate.suggestedMode,
                          onCheckedChanged: (v) =>
                              setState(() => _granted[candidate.hostId] = v),
                          onModeChanged: (mode) =>
                              setState(() => _modes[candidate.hostId] = mode),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Duration:',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                  ),
                  const SizedBox(width: 8),
                  ShadSelect<HostAccessDuration>(
                    key: const Key('mcp_host_access_duration_dropdown'),
                    initialValue: _duration,
                    selectedOptionBuilder: (context, value) =>
                        Text(value.label),
                    options: [
                      for (final d in HostAccessDuration.values)
                        ShadOption(value: d, child: Text(d.label)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _duration = value);
                    },
                  ),
                  const Spacer(),
                  Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: tokens.textSubtle,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Expires in ${_formatRemaining(_remaining)}',
                    style: shellvibeMono(
                      context,
                      size: 11,
                      color: tokens.textSubtle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HostRow extends StatelessWidget {
  final HostAccessCandidate candidate;
  final bool checked;
  final McpAccessMode mode;
  final ValueChanged<bool> onCheckedChanged;
  final ValueChanged<McpAccessMode> onModeChanged;

  const _HostRow({
    required this.candidate,
    required this.checked,
    required this.mode,
    required this.onCheckedChanged,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final isProd = candidate.environment == HostEnvironment.prod;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        // Production rows get a visible tint rather than relying on the
        // small badge alone — this is the row the user is most likely to
        // regret checking without looking twice.
        color: isProd ? tokens.dangerMutedSurface : Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: isProd
            ? Border.all(color: tokens.danger.withValues(alpha: 0.35))
            : null,
      ),
      child: Row(
        children: [
          ShadCheckbox(value: checked, onChanged: onCheckedChanged),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              candidate.label,
              style: shellvibeMono(
                context,
                size: 13,
                weight: FontWeight.w500,
                color: isProd ? tokens.dangerMutedText : tokens.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _EnvironmentBadge(environment: candidate.environment),
          const SizedBox(width: 12),
          Text(
            'mode:',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(width: 4),
          ShadSelect<McpAccessMode>(
            key: Key('mcp_host_access_mode_dropdown_${candidate.hostId}'),
            initialValue: mode,
            selectedOptionBuilder: (context, value) => Text(value.name),
            // `autonomous` is not offered anywhere in v0 (see
            // McpAccessMode.autonomous's own doc comment) — only the two
            // modes v0 actually ships are selectable here.
            options: const [
              ShadOption(
                value: McpAccessMode.readonly,
                child: Text('readonly'),
              ),
              ShadOption(value: McpAccessMode.guarded, child: Text('guarded')),
            ],
            onChanged: (value) {
              if (value != null) onModeChanged(value);
            },
          ),
        ],
      ),
    );
  }
}

class _EnvironmentBadge extends StatelessWidget {
  final HostEnvironment environment;

  const _EnvironmentBadge({required this.environment});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final label = switch (environment) {
      HostEnvironment.prod => 'prod',
      HostEnvironment.staging => 'staging',
      HostEnvironment.dev => 'dev',
    };
    return switch (environment) {
      HostEnvironment.prod => ShadBadge.destructive(child: Text(label)),
      HostEnvironment.staging => ShadBadge.outline(
        foregroundColor: tokens.warning,
        child: Text(label),
      ),
      HostEnvironment.dev => ShadBadge.secondary(child: Text(label)),
    };
  }
}
