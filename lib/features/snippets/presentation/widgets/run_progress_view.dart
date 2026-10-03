import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/runbook_model.dart';
import '../../domain/models/runbook_step_model.dart';
import '../../domain/services/runbook_executor.dart';
import '../../domain/services/runbook_run_service.dart';
import '../notifiers/runbook_run_notifier.dart';

/// Icon and colour of a step's status; a null status is a step not in a run.
(IconData, Color) runStepStatusVisual(
  RunStepStatus? status,
  ShellVibeTokens tokens,
) => switch (status) {
  RunStepStatus.running => (LucideIcons.hourglass, tokens.warning),
  RunStepStatus.success => (LucideIcons.circleCheck, tokens.success),
  RunStepStatus.failed => (LucideIcons.circleX, tokens.danger),
  RunStepStatus.cancelled => (LucideIcons.ban, tokens.textMuted),
  RunStepStatus.pending || null => (LucideIcons.chevronRight, tokens.textMuted),
};

String _hostStatusLabel(RunHostStatus status) => switch (status) {
  RunHostStatus.queued => 'queued',
  RunHostStatus.connecting => 'connecting',
  RunHostStatus.running => 'running',
  RunHostStatus.succeeded => 'succeeded',
  RunHostStatus.failed => 'failed',
  RunHostStatus.cancelled => 'cancelled',
};

ShellVibeStatusTone _hostStatusTone(RunHostStatus status) => switch (status) {
  RunHostStatus.succeeded => ShellVibeStatusTone.success,
  RunHostStatus.failed => ShellVibeStatusTone.danger,
  RunHostStatus.connecting ||
  RunHostStatus.running => ShellVibeStatusTone.warning,
  RunHostStatus.queued ||
  RunHostStatus.cancelled => ShellVibeStatusTone.neutral,
};

/// "2 of 3 hosts succeeded" — and, once settled, what the rest did.
String runSummaryText(ActiveRun run) {
  final total = run.hosts.length;
  final noun = total == 1 ? 'host' : 'hosts';
  final base = '${run.succeededCount} of $total $noun succeeded';
  final cancelled = run.hosts
      .where((h) => h.status == RunHostStatus.cancelled)
      .length;
  return cancelled == 0 ? base : '$base, $cancelled cancelled';
}

/// The live, per-host view of a run: each host with its connection/overall
/// status and its own step statuses, plus Stop while anything is running.
/// Tapping a host or one of its steps opens that host's output.
class RunHostsSection extends ConsumerWidget {
  final ActiveRun run;

  const RunHostsSection({super.key, required this.run});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    final steps = List<RunbookStepModel>.from(run.runbook.steps)
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));

    // Its own Material: the section is also shown inside a ShadDialog, which
    // paints none for the InkWells below.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  run.running
                      ? (run.cancelling ? 'Stopping…' : 'Running…')
                      : runSummaryText(run),
                  key: const Key('run_summary_text'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (run.running)
                ShellVibeButton.secondary(
                  key: const Key('run_stop_button'),
                  label: 'Stop',
                  icon: LucideIcons.square,
                  onPressed: run.cancelling
                      ? null
                      : () => ref.read(runbookRunProvider.notifier).cancel(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final host in run.hosts)
            Container(
              key: Key('run_host_${host.host.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: tokens.border),
                borderRadius: BorderRadius.circular(tokens.radiusSmall),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    key: Key('run_host_open_${host.host.id}'),
                    onTap: () =>
                        showRunOutputDialog(context, run.runbook, host),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            host.host.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ShellVibeStatusChip(
                          label: _hostStatusLabel(host.status),
                          tone: _hostStatusTone(host.status),
                        ),
                      ],
                    ),
                  ),
                  if (host.error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      host.error!,
                      style: TextStyle(color: tokens.danger, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 6),
                  for (final step in steps)
                    InkWell(
                      key: Key('run_step_${host.host.id}_${step.id}'),
                      onTap: () =>
                          showRunOutputDialog(context, run.runbook, host),
                      child: _StepStatusRow(
                        step: step,
                        status: host.steps[step.id],
                        tokens: tokens,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StepStatusRow extends StatelessWidget {
  final RunbookStepModel step;
  final RunStepStatus? status;
  final ShellVibeTokens tokens;

  const _StepStatusRow({
    required this.step,
    required this.status,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color) = runStepStatusVisual(status, tokens);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              step.command,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// One host's output: every step's command, status, exit code and output, and
/// the connection error when it never connected.
Future<void> showRunOutputDialog(
  BuildContext context,
  RunbookModel runbook,
  HostRunState host,
) {
  final steps = List<RunbookStepModel>.from(runbook.steps)
    ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final tokens = ShellVibeTokens.resolve(dialogContext);
      final results = {
        for (final r
            in host.execution?.stepResults ?? const <RunbookStepResult>[])
          r.step.id: r,
      };
      return ShadDialog(
        key: const Key('run_output_dialog'),
        title: Text(host.host.label),
        description: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (host.error != null)
                  SelectableText(
                    host.error!,
                    style: TextStyle(color: tokens.danger, fontSize: 12),
                  ),
                for (final step in steps)
                  _StepOutputBlock(
                    step: step,
                    status: host.steps[step.id],
                    result: results[step.id],
                    tokens: tokens,
                  ),
              ],
            ),
          ),
        ),
        actions: adaptiveDialogActions(dialogContext, [
          ShellVibeButton.secondary(
            label: 'Close',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ]),
        actionsAxis: adaptiveDialogActionsAxis(dialogContext),
      );
    },
  );
}

class _StepOutputBlock extends StatelessWidget {
  final RunbookStepModel step;
  final RunStepStatus? status;
  final RunbookStepResult? result;
  final ShellVibeTokens tokens;

  const _StepOutputBlock({
    required this.step,
    required this.status,
    required this.result,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color) = runStepStatusVisual(status, tokens);
    final result = this.result;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Step ${step.stepOrder}: ${step.command}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            if (result == null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(switch (status) {
                  RunStepStatus.running => 'Running…',
                  RunStepStatus.cancelled => 'Cancelled',
                  _ => 'Not run',
                }, style: TextStyle(color: tokens.textMuted, fontSize: 11)),
              )
            else ...[
              if (result.exitCode != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Exit code ${result.exitCode}',
                    style: TextStyle(color: tokens.textMuted, fontSize: 11),
                  ),
                ),
              if (result.output.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SelectableText(
                    result.output,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              if (result.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SelectableText(
                    result.errorMessage!,
                    style: TextStyle(color: tokens.danger, fontSize: 11),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The run as a dialog: live while running (with Stop), then the summary.
///
/// Watches the notifier rather than taking a snapshot, so it can be opened at
/// the start of a run (a snippet) or at the end (a runbook) and read the same.
class RunResultDialog extends ConsumerWidget {
  const RunResultDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const RunResultDialog(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(runbookRunProvider);
    final tokens = ShellVibeTokens.resolve(context);
    if (run == null) return const SizedBox.shrink();

    final allOk = !run.running && run.succeededCount == run.hosts.length;
    return ShadDialog(
      key: const Key('run_result_dialog'),
      title: Row(
        children: [
          Icon(
            run.running
                ? LucideIcons.hourglass
                : allOk
                ? LucideIcons.circleCheck
                : LucideIcons.circleX,
            color: run.running
                ? tokens.warning
                : allOk
                ? tokens.success
                : tokens.danger,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              run.runbook.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      description: SizedBox(
        width: 520,
        child: SingleChildScrollView(child: RunHostsSection(run: run)),
      ),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          key: const Key('run_result_close'),
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
    );
  }
}
