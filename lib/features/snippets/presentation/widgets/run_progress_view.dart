import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../settings/presentation/notifiers/settings_notifier.dart';
import '../../data/repositories/run_history_repository.dart';
import '../../domain/models/active_run.dart';
import '../../domain/models/runbook_model.dart';
import '../../domain/models/runbook_step_model.dart';
import '../../domain/services/runbook_executor.dart';
import '../../domain/services/runbook_run_service.dart';
import '../../domain/services/snippet_variable_parser.dart';
import 'prod_confirmation.dart';
import '../notifiers/run_history_providers.dart';
import '../notifiers/runbook_run_notifier.dart';
import '../notifiers/runbooks_notifier.dart';
import 'variable_input_dialog.dart';

/// Below this width the host×step matrix does not fit (a phone is 360), and
/// the per-host list takes over.
const double _kMatrixMinWidth = 420;
const double _kHostColumnWidth = 132;
const double _kCellWidth = 44;
const double _kRowHeight = 52;

/// Icon and colour of a step's status; a null status is a step not in a run.
/// The icon always differs by status: colour is never the only signal.
(IconData, Color) runStepStatusVisual(
  RunStepStatus? status,
  ShellVibeTokens tokens,
) => switch (status) {
  RunStepStatus.running => (LucideIcons.hourglass, tokens.warning),
  RunStepStatus.waiting => (LucideIcons.hand, tokens.warning),
  RunStepStatus.success => (LucideIcons.circleCheck, tokens.success),
  RunStepStatus.failed => (LucideIcons.circleX, tokens.danger),
  RunStepStatus.cancelled => (LucideIcons.ban, tokens.textMuted),
  RunStepStatus.skipped => (LucideIcons.skipForward, tokens.textMuted),
  RunStepStatus.pending || null => (LucideIcons.circle, tokens.textMuted),
};

String runStepStatusLabel(RunStepStatus? status) => switch (status) {
  RunStepStatus.running => 'running',
  RunStepStatus.waiting => 'waiting for approval',
  RunStepStatus.success => 'succeeded',
  RunStepStatus.failed => 'failed',
  RunStepStatus.cancelled => 'cancelled',
  RunStepStatus.skipped => 'skipped',
  RunStepStatus.pending || null => 'pending',
};

String _hostStatusLabel(RunHostStatus status) => switch (status) {
  RunHostStatus.queued => 'queued',
  RunHostStatus.connecting => 'connecting',
  RunHostStatus.running => 'running',
  RunHostStatus.succeeded => 'succeeded',
  RunHostStatus.failed => 'failed',
  RunHostStatus.cancelled => 'cancelled',
  RunHostStatus.skipped => 'skipped',
};

ShellVibeStatusTone _hostStatusTone(RunHostStatus status) => switch (status) {
  RunHostStatus.succeeded => ShellVibeStatusTone.success,
  RunHostStatus.failed => ShellVibeStatusTone.danger,
  RunHostStatus.connecting ||
  RunHostStatus.running => ShellVibeStatusTone.warning,
  RunHostStatus.queued ||
  RunHostStatus.cancelled ||
  RunHostStatus.skipped => ShellVibeStatusTone.neutral,
};

/// "3 succeeded · 1 failed · 2 skipped": only the parts that are not zero.
String runSummaryText(ActiveRun run) {
  final inProgress = run.hosts
      .where(
        (h) =>
            h.status == RunHostStatus.connecting ||
            h.status == RunHostStatus.running,
      )
      .length;
  final queued = run.hosts
      .where((h) => h.status == RunHostStatus.queued)
      .length;
  final parts = [
    if (run.succeededCount > 0) '${run.succeededCount} succeeded',
    if (run.failedCount > 0) '${run.failedCount} failed',
    if (run.skippedCount > 0) '${run.skippedCount} skipped',
    if (run.cancelledCount > 0) '${run.cancelledCount} cancelled',
    if (inProgress > 0) '$inProgress running',
    if (queued > 0) '$queued queued',
  ];
  return parts.isEmpty ? 'Starting…' : parts.join(' · ');
}

String formatElapsed(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return m > 0 ? '${m}m ${s}s' : '${d.inSeconds}s';
}

/// "just now", "5m ago", "3h ago", "2d ago".
String relativeTime(DateTime when, DateTime now) {
  final d = now.difference(when);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// A run's progress, live: wires [RunView] to the notifier for Stop and the
/// re-run actions.
class LiveRunView extends ConsumerWidget {
  final ActiveRun run;

  const LiveRunView({super.key, required this.run});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allIds = [for (final h in run.hosts) h.hostId];
    final failedIds = [
      for (final h in run.hosts)
        if (h.status == RunHostStatus.failed) h.hostId,
    ];
    return RunView(
      run: run,
      onStop: () => ref.read(runbookRunProvider.notifier).cancel(),
      onRerunFailed: failedIds.isEmpty
          ? null
          : () => unawaited(
              rerunOnHosts(context, ref, run.runbook, failedIds, run),
            ),
      onRunAgain: () =>
          unawaited(rerunOnHosts(context, ref, run.runbook, allIds, run)),
      onApprove: ref.read(runbookRunProvider.notifier).approve,
    );
  }
}

/// Starts [runbook] again on the saved hosts among [hostIds], with [source]'s
/// variables and strategy. Hosts that no longer exist are dropped, and the
/// user is told.
Future<bool> rerunOnHosts(
  BuildContext context,
  WidgetRef ref,
  RunbookModel runbook,
  List<String> hostIds,
  ActiveRun source,
) async {
  final notifier = ref.read(runbookRunProvider.notifier);
  if (notifier.isRunning) return false;

  // A live run keeps its values in memory, so they are reused. A stored run
  // has none (values are never written to disk), so anything the runbook asks
  // for is asked again, with nothing prefilled.
  final needed = <String>{
    for (final step in runbook.steps)
      ...SnippetVariableParser.extractVariables(step.command),
  };
  final missing = needed
      .where((name) => !source.variableValues.containsKey(name))
      .toList();
  var variableValues = source.variableValues;
  if (missing.isNotEmpty) {
    final entered = await VariableInputDialog.show(
      context,
      variables: missing,
      title: 'Runbook Input Parameters',
    );
    if (entered == null || !context.mounted) return false;
    variableValues = {...variableValues, ...entered};
  }

  final hosts = await notifier.hostsFor(hostIds);
  final dropped = hostIds.length - hosts.length;
  if (!context.mounted) return false;
  if (hosts.isEmpty || dropped > 0) {
    ShadToaster.maybeOf(context)?.show(
      ShadToast(
        description: Text(
          hosts.isEmpty
              ? 'Those hosts no longer exist.'
              : '$dropped ${dropped == 1 ? 'host was' : 'hosts were'} '
                    'deleted and left out.',
        ),
      ),
    );
    if (hosts.isEmpty) return false;
  }
  if (!await confirmProdRun(
    context,
    what:
        '${RunbookRunService.isSnippetRunbook(runbook) ? 'snippet' : 'runbook'}'
        ' "${runbook.title}"',
    hosts: hosts,
  )) {
    return false;
  }
  if (!context.mounted) return false;
  unawaited(
    notifier.start(
      runbook,
      hosts,
      variableValues: variableValues,
      strategy: source.strategy,
    ),
  );
  return true;
}

/// A run, live or read back from history: a summary header, the host×step
/// matrix (or the per-host list when there is no room for it), and the
/// follow-up actions.
class RunView extends StatelessWidget {
  final ActiveRun run;
  final VoidCallback? onStop;
  final VoidCallback? onRerunFailed;
  final VoidCallback? onRunAgain;

  /// Continues an approval step for the whole run.
  final void Function(String stepId)? onApprove;

  /// Label for [onRunAgain]; history says which hosts it will use.
  final String runAgainLabel;

  const RunView({
    super.key,
    required this.run,
    this.onStop,
    this.onRerunFailed,
    this.onRunAgain,
    this.onApprove,
    this.runAgainLabel = 'Run again',
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final steps = List<RunbookStepModel>.from(run.runbook.steps)
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
    final stopped = run.stoppedAfter;

    // Its own Material: the view is also shown inside a ShadDialog, which
    // paints none for the InkWells below.
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useMatrix =
              constraints.maxWidth >= _kMatrixMinWidth &&
              (run.hosts.length > 1 || steps.length > 1);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      run.running
                          ? (run.cancelling ? 'Stopping…' : runSummaryText(run))
                          : runSummaryText(run),
                      key: const Key('run_summary_text'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (run.running && !run.fromHistory && onStop != null)
                    ShellVibeButton.secondary(
                      key: const Key('run_stop_button'),
                      label: 'Stop',
                      icon: LucideIcons.square,
                      onPressed: run.cancelling ? null : onStop,
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 8,
                children: [
                  _ElapsedText(run: run),
                  Text(
                    run.strategy.label,
                    style: TextStyle(color: tokens.textMuted, fontSize: 11),
                  ),
                ],
              ),
              if (stopped != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Stopped after $stopped failed',
                  key: const Key('run_stopped_after'),
                  style: TextStyle(color: tokens.danger, fontSize: 12),
                ),
              ],
              // An approval step a host is waiting at: one Continue releases
              // every host held there, and approves it for any that arrive
              // later.
              for (final step in steps)
                if (step.kind == StepKind.approval &&
                    run.hosts.any(
                      (h) => h.steps[step.id] == RunStepStatus.waiting,
                    ))
                  _ApprovalBanner(
                    step: step,
                    tokens: tokens,
                    onContinue: onApprove == null
                        ? null
                        : () => onApprove!(step.id),
                    onStop: run.cancelling ? null : onStop,
                  ),
              const SizedBox(height: 8),
              if (useMatrix)
                _RunMatrix(run: run, steps: steps, tokens: tokens)
              else
                _RunHostList(run: run, steps: steps, tokens: tokens),
              if (!run.running &&
                  (onRerunFailed != null || onRunAgain != null)) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (onRerunFailed != null)
                      ShellVibeButton.secondary(
                        key: const Key('run_rerun_failed'),
                        label: 'Re-run failed hosts',
                        icon: LucideIcons.refreshCw,
                        onPressed: onRerunFailed,
                      ),
                    if (onRunAgain != null)
                      ShellVibeButton.secondary(
                        key: const Key('run_run_again'),
                        label: runAgainLabel,
                        icon: LucideIcons.play,
                        onPressed: onRunAgain,
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// "Waiting for approval", with Continue and Stop.
class _ApprovalBanner extends StatelessWidget {
  final RunbookStepModel step;
  final ShellVibeTokens tokens;
  final VoidCallback? onContinue;
  final VoidCallback? onStop;

  const _ApprovalBanner({
    required this.step,
    required this.tokens,
    required this.onContinue,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('run_approval_${step.id}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: Border.all(color: tokens.warning.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.hand, size: 14, color: tokens.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Waiting for approval: ${step.command}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ShellVibeButton(
                key: Key('run_approve_${step.id}'),
                label: 'Continue',
                icon: LucideIcons.play,
                onPressed: onContinue,
              ),
              ShellVibeButton.secondary(
                key: Key('run_approval_stop_${step.id}'),
                label: 'Stop',
                icon: LucideIcons.square,
                onPressed: onStop,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Elapsed time, ticking only while the run does: a timer left running on a
/// settled run would keep a widget test from ever settling, and costs a
/// rebuild a second for nothing.
class _ElapsedText extends StatefulWidget {
  final ActiveRun run;
  const _ElapsedText({required this.run});

  @override
  State<_ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<_ElapsedText> {
  Timer? _timer;

  void _sync() {
    if (widget.run.running && _timer == null) {
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else if (!widget.run.running) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_ElapsedText old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Text(
      formatElapsed(widget.run.elapsed(DateTime.now())),
      key: const Key('run_elapsed'),
      style: TextStyle(color: tokens.textMuted, fontSize: 11),
    );
  }
}

/// Rows are hosts, columns are steps. The host column is fixed; the steps
/// scroll sideways, so a long runbook never squeezes the labels.
class _RunMatrix extends StatelessWidget {
  final ActiveRun run;
  final List<RunbookStepModel> steps;
  final ShellVibeTokens tokens;

  const _RunMatrix({
    required this.run,
    required this.steps,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('run_matrix'),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _kHostColumnWidth,
            child: Column(
              children: [
                const SizedBox(height: 28),
                for (final host in run.hosts)
                  _HostHeader(
                    run: run,
                    host: host,
                    steps: steps,
                    tokens: tokens,
                  ),
              ],
            ),
          ),
          Container(
            width: 1,
            color: tokens.border,
            height: 28 + _kRowHeight * run.hosts.length,
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 28,
                    child: Row(
                      children: [
                        for (final step in steps)
                          SizedBox(
                            width: _kCellWidth,
                            child: Tooltip(
                              message: step.kind == StepKind.approval
                                  ? 'Approval: ${step.command}'
                                  : step.command,
                              child: Center(
                                // An approval is its own kind of column.
                                child: step.kind == StepKind.approval
                                    ? Icon(
                                        LucideIcons.userCheck,
                                        key: Key(
                                          'run_header_approval_${step.id}',
                                        ),
                                        size: 14,
                                        color: tokens.warning,
                                      )
                                    : Text(
                                        '${step.stepOrder}',
                                        style: TextStyle(
                                          color: tokens.textMuted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final host in run.hosts)
                    SizedBox(
                      height: _kRowHeight,
                      child: Row(
                        children: [
                          for (final step in steps)
                            _MatrixCell(
                              run: run,
                              host: host,
                              step: step,
                              tokens: tokens,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HostHeader extends StatelessWidget {
  final ActiveRun run;
  final HostRunState host;
  final List<RunbookStepModel> steps;
  final ShellVibeTokens tokens;

  const _HostHeader({
    required this.run,
    required this.host,
    required this.steps,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('run_host_open_${host.hostId}'),
      onTap: () => showRunOutputDialog(context, run.runbook, host),
      child: Container(
        key: Key('run_host_${host.hostId}'),
        height: _kRowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              host.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Text(
              host.error ?? _hostStatusLabel(host.status),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: host.error != null ? tokens.danger : tokens.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatrixCell extends StatelessWidget {
  final ActiveRun run;
  final HostRunState host;
  final RunbookStepModel step;
  final ShellVibeTokens tokens;

  const _MatrixCell({
    required this.run,
    required this.host,
    required this.step,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final status = host.steps[step.id];
    final (icon, color) = runStepStatusVisual(status, tokens);
    final label =
        '${host.label}, step ${step.stepOrder}: ${runStepStatusLabel(status)}';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        key: Key('run_cell_${host.hostId}_${step.id}'),
        onTap: () => showRunOutputDialog(
          context,
          run.runbook,
          host,
          onlyStepId: step.id,
        ),
        child: SizedBox(
          width: _kCellWidth,
          height: _kRowHeight,
          child: Center(child: Icon(icon, size: 18, color: color)),
        ),
      ),
    );
  }
}

/// The narrow-width form: one block per host with its steps beneath.
class _RunHostList extends StatelessWidget {
  final ActiveRun run;
  final List<RunbookStepModel> steps;
  final ShellVibeTokens tokens;

  const _RunHostList({
    required this.run,
    required this.steps,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final host in run.hosts)
          Container(
            key: Key('run_host_${host.hostId}'),
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
                  key: Key('run_host_open_${host.hostId}'),
                  onTap: () => showRunOutputDialog(context, run.runbook, host),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          host.label,
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
                    key: Key('run_step_${host.hostId}_${step.id}'),
                    onTap: () => showRunOutputDialog(
                      context,
                      run.runbook,
                      host,
                      onlyStepId: step.id,
                    ),
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
    return Semantics(
      label: 'step ${step.stepOrder}: ${runStepStatusLabel(status)}',
      child: Padding(
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
      ),
    );
  }
}

/// One host's output: with [onlyStepId], that step alone; otherwise every step
/// plus the connection error when it never connected.
Future<void> showRunOutputDialog(
  BuildContext context,
  RunbookModel runbook,
  HostRunState host, {
  String? onlyStepId,
}) {
  final steps = List<RunbookStepModel>.from(runbook.steps)
    ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _RunOutputDialog(
      title: onlyStepId == null
          ? host.label
          : '${host.label} · step ${steps.firstWhere((s) => s.id == onlyStepId).stepOrder}',
      host: host,
      steps: [
        for (final step in steps)
          if (onlyStepId == null || step.id == onlyStepId) step,
      ],
    ),
  );
}

class _RunOutputDialog extends ConsumerWidget {
  final String title;
  final HostRunState host;
  final List<RunbookStepModel> steps;

  const _RunOutputDialog({
    required this.title,
    required this.host,
    required this.steps,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    return ShadDialog(
      key: const Key('run_output_dialog'),
      title: Text(title),
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
                  result: host.results[step.id],
                  tokens: tokens,
                  onCopy: (text) => _copy(ref, text),
                ),
            ],
          ),
        ),
      ),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
    );
  }

  /// Through the clipboard auto-clear service, like every other copy of
  /// something that may be sensitive: command output is exactly that.
  Future<void> _copy(WidgetRef ref, String text) async {
    final seconds =
        ref.read(settingsProvider).value?.clipboardAutoClearSeconds ?? 30;
    await ref
        .read(clipboardAutoClearServiceProvider)
        .copyAndScheduleClear(text, duration: Duration(seconds: seconds));
  }
}

class _StepOutputBlock extends StatelessWidget {
  final RunbookStepModel step;
  final RunStepStatus? status;
  final RunbookStepResult? result;
  final ShellVibeTokens tokens;
  final void Function(String text) onCopy;

  const _StepOutputBlock({
    required this.step,
    required this.status,
    required this.result,
    required this.tokens,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color) = runStepStatusVisual(status, tokens);
    final result = this.result;
    final muted = TextStyle(color: tokens.textMuted, fontSize: 11);
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
                    'Step ${step.stepOrder}: ${result?.command.isNotEmpty == true ? result!.command : step.command}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  runStepStatusLabel(status),
                  if (result?.exitCode != null) 'Exit code ${result!.exitCode}',
                  if ((result?.attempts ?? 0) > 1)
                    '${result!.attempts} attempts',
                  if (result?.durationMs != null)
                    '${(result!.durationMs! / 1000).toStringAsFixed(1)}s',
                ].join(' · '),
                style: muted,
              ),
            ),
            if (result != null) ...[
              if (result.outputTruncated)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Output truncated: showing the last 16 KiB.',
                    key: const Key('run_output_truncated'),
                    style: muted,
                  ),
                ),
              if (result.output.isNotEmpty) ...[
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
                Align(
                  alignment: Alignment.centerRight,
                  child: ShellVibeButton.secondary(
                    key: const Key('run_output_copy'),
                    label: 'Copy output',
                    icon: LucideIcons.copy,
                    onPressed: () => onCopy(result.output),
                  ),
                ),
              ],
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

    final allOk = !run.running && run.outcome == 'succeeded';
    return ShadDialog(
      key: const Key('run_result_dialog'),
      constraints: const BoxConstraints(maxWidth: 640),
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
        width: double.infinity,
        child: SingleChildScrollView(child: LiveRunView(run: run)),
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

/// A stored run, read-only, with "Run again with these hosts/variables".
class RunHistoryDialog extends ConsumerWidget {
  final RunHistorySummary summary;

  const RunHistoryDialog({super.key, required this.summary});

  static Future<void> show(BuildContext context, RunHistorySummary summary) =>
      showDialog<void>(
        context: context,
        builder: (_) => RunHistoryDialog(summary: summary),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stored = ref.watch(storedRunProvider(summary.id));
    return ShadDialog(
      key: const Key('run_history_dialog'),
      constraints: const BoxConstraints(maxWidth: 640),
      title: Text('${summary.title} · ${_when(summary.startedAt)}'),
      description: SizedBox(
        width: double.infinity,
        child: SingleChildScrollView(
          child: stored.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Could not read this run: $e'),
            data: (run) => run == null
                ? const Text('This run is no longer in the history.')
                : RunView(
                    run: run.run,
                    runAgainLabel: 'Run again with these hosts',
                    onRunAgain: () => unawaited(_runAgain(context, ref, run)),
                  ),
          ),
        ),
      ),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          key: const Key('run_history_close'),
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
    );
  }

  static String _when(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _runAgain(
    BuildContext context,
    WidgetRef ref,
    StoredRun stored,
  ) async {
    // The runbook as it is now when it still exists: the stored one is a
    // snapshot, without the step policies, and the point is to run what the
    // user has today on the same hosts.
    final id = stored.summary.runbookId;
    final current = id == null
        ? null
        : ref
              .read(runbooksProvider)
              .value
              ?.where((r) => r.id == id)
              .firstOrNull;
    final navigator = Navigator.of(context);
    final started = await rerunOnHosts(
      context,
      ref,
      current ?? stored.run.runbook,
      stored.hostIds,
      stored.run,
    );
    if (!started) return;
    // The dialog's own context is gone once it pops; the navigator's is not.
    final host = navigator.context;
    navigator.pop();
    // ignore: use_build_context_synchronously
    unawaited(RunResultDialog.show(host));
  }
}
