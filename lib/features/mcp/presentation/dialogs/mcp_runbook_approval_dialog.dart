import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/mcp_enums.dart';
import '../../domain/models/mcp_models.dart';
import 'mcp_command_approval_dialog.dart';

/// Approval prompt for an agent's `run_runbook`, asked every time.
///
/// It shows everything the run will do before it does it: each step, each
/// target host with its environment (production stands out, and this dialog is
/// the one production confirmation an MCP run gets), the strategy, and the
/// variable values the agent supplied. A secret variable is never in the
/// request: the agent may not pass one, so it appears here as an obscured
/// field the user fills in, and what they type goes to the run and nowhere
/// else.
///
/// Like the command dialog, every way out other than "Approve" (Deny, the
/// barrier, Escape, a back gesture, the countdown) is a refusal.
class McpRunbookApprovalDialog extends StatefulWidget {
  final RunbookApprovalRequest request;
  final DateTime expiresAt;

  const McpRunbookApprovalDialog({
    super.key,
    required this.request,
    required this.expiresAt,
  });

  static Future<RunbookApprovalDecision?> show(
    BuildContext context, {
    required RunbookApprovalRequest request,
    required DateTime expiresAt,
  }) {
    return showDialog<RunbookApprovalDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          McpRunbookApprovalDialog(request: request, expiresAt: expiresAt),
    );
  }

  @override
  State<McpRunbookApprovalDialog> createState() =>
      _McpRunbookApprovalDialogState();
}

class _McpRunbookApprovalDialogState extends State<McpRunbookApprovalDialog> {
  late Timer _ticker;
  late Duration _remaining;
  bool _resolved = false;
  bool _armed = false;
  late final Timer _armTimer;
  final Map<String, TextEditingController> _secrets = {};
  final Set<String> _missing = {};

  @override
  void initState() {
    super.initState();
    _armTimer = Timer(mcpApprovalArmDelay, () {
      if (mounted) setState(() => _armed = true);
    });
    for (final field in widget.request.secretFields) {
      _secrets[field.name] = TextEditingController();
    }
    _remaining = widget.expiresAt.difference(DateTime.now().toUtc());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker.cancel();
    _armTimer.cancel();
    for (final c in _secrets.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _tick() {
    final remaining = widget.expiresAt.difference(DateTime.now().toUtc());
    if (remaining.isNegative || remaining == Duration.zero) {
      _ticker.cancel();
      _resolve(RunbookApprovalDecision.denied);
      return;
    }
    if (mounted) setState(() => _remaining = remaining);
  }

  void _resolve(RunbookApprovalDecision decision) {
    if (_resolved || !mounted) return;
    _resolved = true;
    Navigator.of(context).pop(decision);
  }

  void _approve() {
    final missing = {
      for (final field in widget.request.secretFields)
        if (field.required && _secrets[field.name]!.text.isEmpty) field.name,
    };
    if (missing.isNotEmpty) {
      setState(() {
        _missing
          ..clear()
          ..addAll(missing);
      });
      return;
    }
    _resolve(
      RunbookApprovalDecision(
        approved: true,
        secretValues: {
          for (final field in widget.request.secretFields)
            if (_secrets[field.name]!.text.isNotEmpty)
              field.name: _secrets[field.name]!.text,
        },
      ),
    );
  }

  String _formatRemaining(Duration d) {
    final clamped = d.isNegative ? Duration.zero : d;
    return '${clamped.inMinutes}m '
        '${(clamped.inSeconds % 60).toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final request = widget.request;
    final bodyStyle = Theme.of(context).textTheme.bodySmall;
    final prod = [
      for (final h in request.hosts)
        if (h.environment == HostEnvironment.prod) h,
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _resolve(RunbookApprovalDecision.denied);
      },
      child: ShadDialog(
        key: const Key('mcp_runbook_approval_dialog'),
        constraints: const BoxConstraints(maxWidth: 560),
        title: const Text('Run this runbook?'),
        description: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${request.clientName} wants to run "${request.runbookTitle}"',
            style: bodyStyle?.copyWith(color: tokens.textSecondary),
          ),
        ),
        actions: adaptiveDialogActions(context, [
          ShellVibeButton.secondary(
            key: const Key('mcp_runbook_deny_button'),
            label: 'Deny',
            onPressed: () => _resolve(RunbookApprovalDecision.denied),
          ),
          if (prod.isNotEmpty)
            ShellVibeButton.danger(
              key: const Key('mcp_runbook_approve_button'),
              label: 'Run on production',
              onPressed: _armed ? _approve : null,
            )
          else
            ShellVibeButton(
              key: const Key('mcp_runbook_approve_button'),
              label: 'Approve',
              onPressed: _armed ? _approve : null,
            ),
        ]),
        actionsAxis: adaptiveDialogActionsAxis(context),
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.6,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  if (prod.isNotEmpty)
                    Container(
                      key: const Key('mcp_runbook_prod_banner'),
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: tokens.danger.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(
                          tokens.radiusMedium,
                        ),
                        border: Border.all(
                          color: tokens.danger.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        'This run includes production: '
                        '${prod.map((h) => h.label).join(', ')}.',
                        style: bodyStyle?.copyWith(
                          color: tokens.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Text(
                    'Hosts · ${request.strategyLabel}',
                    style: bodyStyle?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final host in request.hosts)
                    Padding(
                      key: Key('mcp_runbook_host_${host.id}'),
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              host.label,
                              style: shellvibeMono(
                                context,
                                size: 13,
                                color: tokens.textPrimary,
                              ),
                            ),
                          ),
                          McpEnvironmentBadge(environment: host.environment),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Steps',
                    style: bodyStyle?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final step in request.steps)
                    Container(
                      key: Key('mcp_runbook_step_${step.order}'),
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: tokens.terminalBg,
                        borderRadius: BorderRadius.circular(
                          tokens.radiusMedium,
                        ),
                        border: Border.all(color: tokens.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            switch (step.kind) {
                              'approval' =>
                                '${step.order}. Waits for you to continue',
                              'snippet' => '${step.order}. Snippet',
                              _ => '${step.order}. Command',
                            },
                            style: bodyStyle?.copyWith(color: tokens.textMuted),
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            step.text,
                            style: shellvibeMono(
                              context,
                              size: 12,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (request.variables.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Values supplied by the agent',
                      style: bodyStyle?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final entry in request.variables.entries)
                      Text(
                        '${entry.key} = ${visibleControlChars(entry.value)}',
                        key: Key('mcp_runbook_value_${entry.key}'),
                        style: shellvibeMono(
                          context,
                          size: 12,
                          color: tokens.textPrimary,
                        ),
                      ),
                  ],
                  if (request.secretFields.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Secrets only you can enter',
                      style: bodyStyle?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    for (final field in request.secretFields)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              field.label +
                                  (field.required ? '' : ' (optional)'),
                              style: bodyStyle,
                            ),
                            const SizedBox(height: 2),
                            ShadInput(
                              key: Key('mcp_runbook_secret_${field.name}'),
                              controller: _secrets[field.name],
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              placeholder: const Text('Hidden as you type'),
                            ),
                            if (_missing.contains(field.name))
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Required',
                                  key: Key(
                                    'mcp_runbook_secret_error_${field.name}',
                                  ),
                                  style: bodyStyle?.copyWith(
                                    color: tokens.danger,
                                  ),
                                ),
                              ),
                          ],
                        ),
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
        ),
      ),
    );
  }
}
