import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/mcp_enums.dart';
import '../../domain/models/mcp_models.dart';

/// How long a freshly shown approval dialog keeps its approve action off.
/// Dialogs queue back to back, so without it a double-click or a quick
/// second click meant for one request could land on the next one, unread.
const mcpApprovalArmDelay = Duration(milliseconds: 700);

/// [text] with everything a reader could miss made visible, for showing
/// agent-supplied text in an approval dialog: each line break ends in `⏎`,
/// a tab shows as `⇥`, and control or invisible formatting characters (bidi
/// overrides, zero-width marks, line separators) show as `⟨U+XXXX⟩`.
String visibleControlChars(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    if (rune == 0x0A) {
      out.write('⏎\n');
    } else if (rune == 0x09) {
      out.write('⇥');
    } else if (rune < 0x20 ||
        (rune >= 0x7F && rune < 0xA0) ||
        _isInvisibleFormat(rune)) {
      final hex = rune.toRadixString(16).toUpperCase().padLeft(4, '0');
      out.write('⟨U+$hex⟩');
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

bool _isInvisibleFormat(int rune) =>
    rune == 0xAD ||
    (rune >= 0x200B && rune <= 0x200F) ||
    (rune >= 0x2028 && rune <= 0x202E) ||
    (rune >= 0x2060 && rune <= 0x2069) ||
    rune == 0xFEFF;

/// Human-readable label for one [RiskCategory], for the approval dialog and
/// nowhere else — [RiskCategory.wireName] stays the machine-facing name used
/// in the audit log and the agent's error payloads.
String riskCategoryLabel(RiskCategory category) => switch (category) {
  RiskCategory.readonlySafe => 'Read-only',
  RiskCategory.destructiveFs => 'Destructive filesystem change',
  RiskCategory.privilege => 'Privilege escalation',
  RiskCategory.serviceControl => 'Service control',
  RiskCategory.package => 'Package install or removal',
  RiskCategory.identityPerm => 'Identity or permission change',
  RiskCategory.networkFw => 'Firewall or network change',
  RiskCategory.database => 'Database mutation',
  RiskCategory.vcs => 'Version control history change',
  RiskCategory.container => 'Container or cluster removal',
  RiskCategory.opaqueExec => 'Opaque execution (content unreadable)',
  RiskCategory.interactive => 'Interactive command',
  RiskCategory.secretRead => 'Reads credential material',
  RiskCategory.unclassified => 'Unclassified (treated as risky)',
};

/// Why this particular command may not be remembered, when it may not be.
///
/// [CommandApprovalRequest.canRemember] is a plain bool — it says *that* the
/// remember options are off, not *why*. The paths that turn it off are
/// pinned down in docs/mcp_plan.md "Onay hatırlama semantiği" and echoed in
/// [CommandApprovalRequest]'s own doc comment, so they are reconstructed here
/// from [CommandApprovalRequest.environment] and [CommandApprovalRequest.category]
/// well enough to show the user which rule fired, rather than just that one did.
String _cannotRememberReason(CommandApprovalRequest request) {
  if (request.environment == HostEnvironment.prod &&
      request.category.isDestructive) {
    return 'This command cannot be remembered: destructive action on a '
        'production host.';
  }
  if (request.category == RiskCategory.opaqueExec) {
    return "This command cannot be remembered: its effect can't be read "
        'from the command text.';
  }
  if (request.category == RiskCategory.secretRead) {
    return 'This command cannot be remembered: it reads credential '
        'material.';
  }
  return 'This command cannot be remembered.';
}

/// Single-command approval prompt, shown for every `confirm` policy
/// decision. See docs/mcp_plan.md "Erişim onayı akışı" and "Onay hatırlama
/// semantiği".
///
/// Every way of leaving this dialog other than pressing "Approve" — "Deny",
/// the barrier (blocked), Escape, a back gesture, or the countdown reaching
/// zero — resolves to [ApprovalDecision.denied]. There is no path out of this
/// widget that runs the command without an explicit approval.
class McpCommandApprovalDialog extends StatefulWidget {
  final CommandApprovalRequest request;

  /// Wall-clock deadline this prompt fails closed at, mirrored from
  /// [PendingCommandApproval.expiresAt].
  final DateTime expiresAt;

  const McpCommandApprovalDialog({
    super.key,
    required this.request,
    required this.expiresAt,
  });

  static Future<ApprovalDecision?> show(
    BuildContext context, {
    required CommandApprovalRequest request,
    required DateTime expiresAt,
  }) {
    return showDialog<ApprovalDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          McpCommandApprovalDialog(request: request, expiresAt: expiresAt),
    );
  }

  @override
  State<McpCommandApprovalDialog> createState() =>
      _McpCommandApprovalDialogState();
}

class _McpCommandApprovalDialogState extends State<McpCommandApprovalDialog> {
  ApprovalScope _scope = ApprovalScope.once;
  late Timer _ticker;
  late Duration _remaining;
  bool _resolved = false;
  bool _armed = false;
  late final Timer _armTimer;
  final _commandScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _remaining = widget.expiresAt.difference(DateTime.now().toUtc());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _armTimer = Timer(mcpApprovalArmDelay, () {
      if (mounted) setState(() => _armed = true);
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    _armTimer.cancel();
    _commandScroll.dispose();
    super.dispose();
  }

  void _tick() {
    final remaining = widget.expiresAt.difference(DateTime.now().toUtc());
    if (remaining.isNegative || remaining == Duration.zero) {
      _ticker.cancel();
      _resolve(ApprovalDecision.denied);
      return;
    }
    if (mounted) setState(() => _remaining = remaining);
  }

  void _resolve(ApprovalDecision decision) {
    if (_resolved || !mounted) return;
    _resolved = true;
    Navigator.of(context).pop(decision);
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
    final bodyStyle = Theme.of(context).textTheme.bodySmall;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _resolve(ApprovalDecision.denied);
      },
      child: ShadDialog(
        constraints: const BoxConstraints(maxWidth: 520),
        title: const Text('Approve command?'),
        description: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Requested by ${request.clientName}',
            style: bodyStyle?.copyWith(color: tokens.textSecondary),
          ),
        ),
        actions: adaptiveDialogActions(context, [
          ShellVibeButton.secondary(
            key: const Key('mcp_command_deny_button'),
            label: 'Deny',
            onPressed: () => _resolve(ApprovalDecision.denied),
          ),
          ShellVibeButton(
            key: const Key('mcp_command_approve_button'),
            label: 'Approve',
            onPressed: _armed
                ? () => _resolve(
                    ApprovalDecision(
                      approved: true,
                      scope: request.canRemember ? _scope : ApprovalScope.once,
                    ),
                  )
                : null,
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      request.hostLabel,
                      style: shellvibeMono(
                        context,
                        size: 13,
                        weight: FontWeight.w500,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                  McpEnvironmentBadge(environment: request.environment),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'cwd: ${request.cwd}',
                style: shellvibeMono(
                  context,
                  size: 12,
                  color: tokens.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: tokens.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    riskCategoryLabel(request.category),
                    style: bodyStyle?.copyWith(color: tokens.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tokens.terminalBg,
                  borderRadius: BorderRadius.circular(tokens.radiusMedium),
                  border: Border.all(color: tokens.border),
                ),
                // The whole command, always: every line and every character
                // the shell will run must be on screen before approval.
                // Real line breaks are marked with `⏎`, so a soft wrap can
                // be told apart from a second command; anything longer than
                // the box scrolls with a visible scrollbar.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: Scrollbar(
                    controller: _commandScroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _commandScroll,
                      child: SelectableText(
                        visibleControlChars(request.command),
                        key: const Key('mcp_command_text'),
                        style: shellvibeMono(
                          context,
                          size: 13,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (request.command.contains('\n')) ...[
                const SizedBox(height: 6),
                Text(
                  '${'\n'.allMatches(request.command).length + 1} lines — '
                  'every line runs',
                  key: const Key('mcp_command_multiline_warning'),
                  style: bodyStyle?.copyWith(color: tokens.warning),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Remember this decision',
                style: bodyStyle?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Material(
                type: MaterialType.transparency,
                child: ShadRadioGroup<ApprovalScope>(
                  key: const Key('mcp_command_remember_scope_group'),
                  initialValue: _scope,
                  axis: Axis.horizontal,
                  spacing: 16,
                  onChanged: (value) {
                    if (value != null) setState(() => _scope = value);
                  },
                  items: [
                    for (final scope in ApprovalScope.values)
                      ShadRadio<ApprovalScope>(
                        key: Key('mcp_command_remember_scope_${scope.name}'),
                        value: scope,
                        // `once` is always available; every other option is
                        // the one mechanism keeping an approve-everything
                        // reflex from reaching production, so it is greyed
                        // out rather than hidden — the user needs to see the
                        // rule exists, not just its absence.
                        enabled:
                            request.canRemember || scope == ApprovalScope.once,
                        label: Text(_scopeLabel(scope)),
                      ),
                  ],
                ),
              ),
              if (!request.canRemember) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: tokens.textSubtle,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _cannotRememberReason(request),
                        style: bodyStyle?.copyWith(
                          color: tokens.textSubtle,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
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

  String _scopeLabel(ApprovalScope scope) => switch (scope) {
    ApprovalScope.once => 'Once',
    ApprovalScope.fifteenMinutes => '15 minutes',
    ApprovalScope.session => 'This session',
    ApprovalScope.always => 'Always',
  };
}

class McpEnvironmentBadge extends StatelessWidget {
  final HostEnvironment environment;

  const McpEnvironmentBadge({super.key, required this.environment});

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
