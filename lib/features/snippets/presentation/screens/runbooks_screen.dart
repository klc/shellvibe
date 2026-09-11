import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../domain/models/runbook_model.dart';
import '../../domain/models/runbook_step_model.dart';
import '../../domain/services/runbook_executor.dart';
import '../../domain/services/snippet_variable_parser.dart';
import '../notifiers/runbooks_notifier.dart';
import '../widgets/runbook_editor_dialog.dart';
import '../widgets/variable_input_dialog.dart';

/// Column weights shared by the runbook list header and its rows.
const List<int> _kRunbookColumnFlex = [4, 5, 2];

/// Rendered width of the row's trailing controls.
///
/// Measured, not guessed: a [ShellVibeIconButton] occupies one control height
/// (34px under a pointer) and the [PopupMenuButton] 48px once Material's
/// minimum tap target is applied, plus the 12px the popup adds around its icon.
const double _kRunbookActionsWidth = 94;

/// The runbooks half of the automation library.
///
/// It renders the list and its detail drawer only: the surrounding shell —
/// context column, toolbar, search field and the Add action — belongs to
/// `SnippetsScreen`, so both sections sit inside one module rather than
/// carrying two different page chromes.
class RunbooksScreen extends ConsumerStatefulWidget {
  final String? workspaceId;
  final Future<(String output, int exitCode)> Function(
    String command,
    int timeoutSeconds,
  )?
  customCommandRunner;

  /// Lower-cased query owned by the shell's search field.
  final String searchQuery;

  /// True when the viewport is too narrow for the context column.
  final bool compact;

  /// True when the viewport can host the inline detail drawer.
  final bool showDetailDrawer;

  const RunbooksScreen({
    super.key,
    this.workspaceId,
    this.customCommandRunner,
    this.searchQuery = '',
    this.compact = true,
    this.showDetailDrawer = false,
  });

  @override
  ConsumerState<RunbooksScreen> createState() => _RunbooksScreenState();
}

class _RunbooksScreenState extends ConsumerState<RunbooksScreen> {
  final Map<String, String> _stepStatuses = {};
  bool _isExecuting = false;
  String? _executingRunbookId;
  String? _selectedRunbookId;

  String get _workspaceId =>
      widget.workspaceId ?? ref.read(activeWorkspaceIdProvider);

  @override
  Widget build(BuildContext context) {
    final runbooksAsync = ref.watch(runbooksProvider);
    final tokens = ShellVibeTokens.resolve(context);

    return runbooksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => ShellVibeEmptyState(
        icon: LucideIcons.triangleAlert,
        title: 'Runbooks could not be loaded',
        description: '$error',
      ),
      data: (runbooks) {
        if (runbooks.isEmpty) {
          return ShellVibeEmptyState(
            icon: LucideIcons.listChecks,
            title: 'No runbooks defined.',
            description:
                'Chain commands into a multi-step workflow that reports where '
                'it stopped.',
            actions: [
              // Flexible, not a bare Text: a shadcn button shrink-wraps its
              // label, so at a large system text scale an unbounded one
              // overflows the button it sits in.
              ShellVibeButton(
                label: 'Add runbook',
                icon: LucideIcons.plus,
                onPressed: _openEditor,
              ),
            ],
          );
        }

        final visible = _visibleRunbooks(runbooks);
        if (visible.isEmpty) {
          return const ShellVibeEmptyState(
            icon: LucideIcons.searchX,
            title: 'No runbooks match your search.',
            description: 'Try another word from the title or description.',
          );
        }

        final selected = visible
            .where((runbook) => runbook.id == _selectedRunbookId)
            .firstOrNull;

        return Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  _RunbookListHeader(tokens: tokens, compact: widget.compact),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final runbook = visible[index];
                        return _RunbookRow(
                          key: ValueKey(runbook.id),
                          runbook: runbook,
                          compact: widget.compact,
                          selected: runbook.id == _selectedRunbookId,
                          isExecuting:
                              _isExecuting && _executingRunbookId == runbook.id,
                          onSelect: () {
                            setState(() => _selectedRunbookId = runbook.id);
                            // Too narrow for the inline drawer, so the step
                            // list becomes a sheet rather than a selection
                            // that leads nowhere.
                            if (!widget.showDetailDrawer) {
                              _showDetailSheet(runbook);
                            }
                          },
                          onRun: () => _executeRunbook(runbook),
                          onEdit: () => _openEditor(runbook: runbook),
                          onDelete: () => _deleteRunbook(runbook),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (widget.showDetailDrawer && selected != null)
              ShellVibeDetailDrawer(
                child: _RunbookDetailPanel(
                  runbook: selected,
                  stepStatuses: _stepStatuses,
                  isExecuting:
                      _isExecuting && _executingRunbookId == selected.id,
                  onRun: () => _executeRunbook(selected),
                  onEdit: () => _openEditor(runbook: selected),
                  onDelete: () => _deleteRunbook(selected),
                  onClose: () => setState(() => _selectedRunbookId = null),
                ),
              ),
          ],
        );
      },
    );
  }

  List<RunbookModel> _visibleRunbooks(List<RunbookModel> runbooks) {
    if (widget.searchQuery.isEmpty) return runbooks;
    return runbooks.where((runbook) {
      return runbook.title.toLowerCase().contains(widget.searchQuery) ||
          (runbook.description ?? '').toLowerCase().contains(
            widget.searchQuery,
          ) ||
          runbook.steps.any(
            (step) => step.command.toLowerCase().contains(widget.searchQuery),
          );
    }).toList();
  }

  /// The narrow-width form of the detail drawer.
  void _showDetailSheet(RunbookModel runbook) {
    final tokens = ShellVibeTokens.resolve(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: tokens.surface,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: _RunbookDetailPanel(
            runbook: runbook,
            stepStatuses: _stepStatuses,
            isExecuting: _isExecuting && _executingRunbookId == runbook.id,
            onRun: () {
              Navigator.of(sheetContext).pop();
              _executeRunbook(runbook);
            },
            onEdit: () {
              Navigator.of(sheetContext).pop();
              _openEditor(runbook: runbook);
            },
            onDelete: () {
              Navigator.of(sheetContext).pop();
              _deleteRunbook(runbook);
            },
            onClose: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor({RunbookModel? runbook}) async {
    final workspaceId = _workspaceId;
    final result = await RunbookEditorDialog.show(
      context,
      runbook: runbook,
      workspaceId: workspaceId,
    );
    if (!mounted) return;
    if (result == null) return;

    final notifier = ref.read(runbooksProvider.notifier);
    if (runbook == null) {
      await notifier.addRunbook(
        workspaceId: result.workspaceId,
        title: result.title,
        description: result.description,
        steps: result.steps,
      );
    } else {
      await notifier.updateRunbook(result);
    }
  }

  Future<void> _deleteRunbook(RunbookModel runbook) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ShadDialog.alert(
        title: const Text('Delete Runbook'),
        description: Text(
          'Are you sure you want to delete "${runbook.title}"?',
        ),
        actions: adaptiveDialogActions(context, [
          ShellVibeButton.secondary(
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          ShellVibeButton.danger(
            label: 'Delete',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ]),
        actionsAxis: adaptiveDialogActionsAxis(context),
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    if (_selectedRunbookId == runbook.id) {
      setState(() => _selectedRunbookId = null);
    }
    await ref.read(runbooksProvider.notifier).deleteRunbook(runbook.id);
  }

  Future<void> _executeRunbook(RunbookModel runbook) async {
    // 1. Gather all unique variables across all steps
    final allVars = <String>{};
    for (final step in runbook.steps) {
      allVars.addAll(SnippetVariableParser.extractVariables(step.command));
    }

    Map<String, String> variableValues = {};
    if (allVars.isNotEmpty) {
      final inputs = await VariableInputDialog.show(
        context,
        variables: allVars.toList(),
        title: 'Runbook Input Parameters',
      );
      if (!mounted) return;
      if (inputs == null) return; // User cancelled
      variableValues = inputs;
    }

    setState(() {
      _isExecuting = true;
      _executingRunbookId = runbook.id;
      // Selecting the running runbook keeps its step progress on screen.
      _selectedRunbookId = runbook.id;
      _stepStatuses.clear();
    });

    final commandRunner =
        widget.customCommandRunner ??
        (String command, int timeoutSeconds) async {
          // Default fallback runner simulation if no active terminal runner passed
          await Future.delayed(const Duration(milliseconds: 500));
          return ('Executed: $command\nStatus: OK', 0);
        };

    final result = await ref
        .read(runbooksProvider.notifier)
        .executeRunbook(
          runbook,
          commandRunner,
          variableValues: variableValues,
          onProgress: (RunbookStepModel step, String status) {
            if (mounted) {
              setState(() {
                _stepStatuses[step.id] = status;
              });
            }
          },
        );

    if (mounted) {
      setState(() {
        _isExecuting = false;
        _executingRunbookId = null;
      });

      _showResultDialog(result);
    }
  }

  void _showResultDialog(RunbookExecutionResult result) {
    final tokens = ShellVibeTokens.resolve(context);
    showDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: Row(
          children: [
            Icon(
              result.overallSuccess
                  ? LucideIcons.circleCheck
                  : LucideIcons.circleX,
              color: result.overallSuccess ? tokens.success : tokens.danger,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                result.overallSuccess ? 'Runbook Succeeded' : 'Runbook Failed',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        description: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: result.stepResults.map((sr) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: sr.success
                          ? tokens.success.withValues(alpha: 0.1)
                          : tokens.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(tokens.radiusSmall),
                      border: Border.all(
                        color: sr.success ? tokens.success : tokens.danger,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Step ${sr.step.stepOrder}: ${sr.step.command}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text('Status: ${sr.success ? "SUCCESS" : "FAILED"}'),
                        if (sr.output.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            sr.output,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ],
                        if (sr.errorMessage != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            sr.errorMessage!,
                            style: TextStyle(
                              color: tokens.danger,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
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
      ),
    );
  }
}

class _RunbookListHeader extends StatelessWidget {
  final ShellVibeTokens tokens;
  final bool compact;

  const _RunbookListHeader({required this.tokens, required this.compact});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontSize: 10,
      letterSpacing: 0.8,
      color: tokens.textMuted,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _kRunbookColumnFlex[0],
            child: Text('NAME', style: style, maxLines: 1),
          ),
          Expanded(
            flex: _kRunbookColumnFlex[1],
            child: Text('DESCRIPTION', style: style, maxLines: 1),
          ),
          if (!compact)
            Expanded(
              flex: _kRunbookColumnFlex[2],
              child: Text('STEPS', style: style, maxLines: 1),
            ),
          const SizedBox(width: _kRunbookActionsWidth),
        ],
      ),
    );
  }
}

/// Single-line dense runbook row.
class _RunbookRow extends StatelessWidget {
  final RunbookModel runbook;
  final bool compact;
  final bool selected;
  final bool isExecuting;
  final VoidCallback onSelect;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RunbookRow({
    super.key,
    required this.runbook,
    required this.compact,
    required this.selected,
    required this.isExecuting,
    required this.onSelect,
    required this.onRun,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final mutedStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: tokens.textMuted, fontSize: 12);
    final stepLabel = runbook.steps.length == 1
        ? '1 step'
        : '${runbook.steps.length} steps';

    return Semantics(
      button: true,
      selected: selected,
      label: '${runbook.title}, runbook with $stepLabel',
      child: InkWell(
        key: Key('runbook_tile_${runbook.id}'),
        onTap: onSelect,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          constraints: const BoxConstraints(minHeight: 42),
          decoration: BoxDecoration(
            color: selected
                ? tokens.textPrimary.withValues(alpha: 0.06)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(color: tokens.border),
              left: BorderSide(
                color: selected ? tokens.brand : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: _kRunbookColumnFlex[0],
                child: Text(
                  runbook.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                flex: _kRunbookColumnFlex[1],
                child: Text(
                  // Compact drops the step column, so the count that would be
                  // lost moves onto the description line.
                  compact
                      ? [
                          if (runbook.description?.isNotEmpty ?? false)
                            runbook.description!,
                          stepLabel,
                        ].join(' · ')
                      : (runbook.description?.isNotEmpty ?? false)
                      ? runbook.description!
                      : '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mutedStyle,
                ),
              ),
              if (!compact)
                Expanded(
                  flex: _kRunbookColumnFlex[2],
                  child: Text(
                    // Status is never carried by colour alone: the spinner is
                    // paired with this text so the row still reads without it.
                    isExecuting ? 'running' : stepLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mutedStyle,
                  ),
                ),
              SizedBox(
                width: _kRunbookActionsWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isExecuting)
                      const Padding(
                        padding: EdgeInsets.all(9),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      ShellVibeIconButton(
                        key: Key('runbook_execute_${runbook.id}'),
                        icon: LucideIcons.play,
                        tooltip: 'Run runbook',
                        onPressed: onRun,
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'Runbook actions',
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      icon: const Icon(LucideIcons.ellipsis, size: 16),
                      onSelected: (value) {
                        if (value == 'edit') onEdit();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(LucideIcons.pencil, size: 16),
                              SizedBox(width: 8),
                              Text('Edit runbook'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.trash2,
                                size: 16,
                                color: tokens.danger,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Delete runbook',
                                style: TextStyle(color: tokens.danger),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline right-hand detail panel for a runbook.
///
/// This is also where a run reports itself: the step list carries the live
/// per-step status instead of an expanding card in the list.
class _RunbookDetailPanel extends StatelessWidget {
  final RunbookModel runbook;
  final Map<String, String> stepStatuses;
  final bool isExecuting;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  const _RunbookDetailPanel({
    required this.runbook,
    required this.stepStatuses,
    required this.isExecuting,
    required this.onRun,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);

    return ListView(
      key: const Key('runbook_detail_drawer'),
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    runbook.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (runbook.description?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 2),
                    Text(
                      runbook.description!,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: tokens.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            ShellVibeIconButton(
              icon: LucideIcons.x,
              tooltip: 'Close details',
              onPressed: onClose,
            ),
          ],
        ),
        const SizedBox(height: 6),
        ShellVibeStatusChip(
          label: isExecuting ? 'running' : 'idle',
          tone: isExecuting
              ? ShellVibeStatusTone.warning
              : ShellVibeStatusTone.neutral,
        ),
        const SizedBox(height: 12),
        ShellVibeButton(
          key: const Key('runbook_detail_run'),
          label: 'Run runbook',
          icon: LucideIcons.play,
          onPressed: onRun,
          expand: true,
          busy: isExecuting,
        ),
        const SizedBox(height: 8),
        ShellVibeButton.secondary(
          key: const Key('runbook_detail_edit'),
          label: 'Edit',
          onPressed: onEdit,
          expand: true,
        ),
        const SizedBox(height: 14),
        const ShellVibeSectionLabel(label: 'Steps', padding: EdgeInsets.zero),
        const SizedBox(height: 6),
        for (final step in runbook.steps)
          _RunbookStepTile(
            step: step,
            status: stepStatuses[step.id],
            tokens: tokens,
          ),
        const SizedBox(height: 14),
        ShellVibeButton.danger(
          key: const Key('runbook_detail_delete'),
          label: 'Delete runbook',
          onPressed: onDelete,
          expand: true,
        ),
      ],
    );
  }
}

class _RunbookStepTile extends StatelessWidget {
  final RunbookStepModel step;
  final String? status;
  final ShellVibeTokens tokens;

  const _RunbookStepTile({
    required this.step,
    required this.status,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final (statusIcon, statusColor) = switch (status) {
      'running' => (LucideIcons.hourglass, tokens.warning),
      'success' => (LucideIcons.circleCheck, tokens.success),
      'failed' => (LucideIcons.circleX, tokens.danger),
      _ => (LucideIcons.chevronRight, tokens.textMuted),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(statusIcon, size: 14, color: statusColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.command,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                if (step.expectedOutputPattern != null) ...[
                  const SizedBox(height: 4),
                  ShellVibeStatusChip(
                    label: 'expects ${step.expectedOutputPattern}',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
