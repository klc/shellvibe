import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../workspaces/presentation/providers/workspace_provider.dart';
import '../../data/repositories/run_history_repository.dart';
import '../../domain/models/runbook_model.dart';
import '../../domain/models/runbook_step_model.dart';
import '../../domain/services/run_variables.dart';
import '../notifiers/snippets_notifier.dart';
import '../../../templates/presentation/template_launch.dart';
import '../notifiers/run_history_providers.dart';
import '../notifiers/runbook_run_notifier.dart';
import '../notifiers/runbooks_notifier.dart';
import '../widgets/automation_list_parts.dart';
import '../widgets/automation_section_layout.dart';
import '../widgets/run_progress_view.dart';
import '../widgets/run_history_section.dart';
import '../widgets/run_target_sheet.dart';
import '../widgets/runbook_editor_dialog.dart';
import '../widgets/runbook_markdown_actions.dart';
import '../widgets/variable_input_dialog.dart';

/// Column weights shared by the runbook list header and its rows.
const List<int> _kRunbookColumnFlex = [4, 5, 2];

/// The runbooks half of the automation library.
///
/// It renders the list and its detail drawer only: the surrounding shell —
/// context column, toolbar, search field and the Add action — belongs to
/// `SnippetsScreen`, so both sections sit inside one module rather than
/// carrying two different page chromes.
class RunbooksScreen extends ConsumerStatefulWidget {
  final String? workspaceId;

  /// The toolbar `SnippetsScreen` shares between its sections, laid out in
  /// this section's slab so the detail drawer can sit beside it.
  final Widget header;

  /// Lower-cased query owned by the shell's search field.
  final String searchQuery;

  /// The tag the shell is filtering to, or null for every runbook.
  final String? selectedTag;

  /// True when the viewport is too narrow for the context column.
  final bool compact;

  /// True when the viewport can host the inline detail drawer.
  final bool showDetailDrawer;

  const RunbooksScreen({
    super.key,
    this.workspaceId,
    this.header = const SizedBox.shrink(),
    this.searchQuery = '',
    this.selectedTag,
    this.compact = true,
    this.showDetailDrawer = false,
  });

  @override
  ConsumerState<RunbooksScreen> createState() => _RunbooksScreenState();
}

class _RunbooksScreenState extends ConsumerState<RunbooksScreen> {
  String? _selectedRunbookId;

  String get _workspaceId =>
      widget.workspaceId ?? ref.read(activeWorkspaceIdProvider);

  @override
  Widget build(BuildContext context) {
    final runbooksAsync = ref.watch(runbooksProvider);
    final activeRun = ref.watch(runbookRunProvider);
    final lastRuns =
        ref.watch(latestRunbookRunsProvider).value ??
        const <String, RunHistorySummary>{};
    bool isRunning(RunbookModel runbook) =>
        activeRun != null &&
        activeRun.running &&
        activeRun.runbook.id == runbook.id;

    Widget layout(Widget body, {Widget? drawer}) => AutomationSectionLayout(
      header: widget.header,
      body: body,
      drawer: drawer,
      framed: !widget.compact,
    );

    return runbooksAsync.when(
      loading: () => layout(const Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => layout(
        ShellVibeEmptyState(
          icon: LucideIcons.triangleAlert,
          title: 'Runbooks could not be loaded',
          description: '$error',
        ),
      ),
      data: (runbooks) {
        if (runbooks.isEmpty) {
          return layout(
            ShellVibeEmptyState(
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
                  label: 'Add Runbook',
                  icon: LucideIcons.plus,
                  onPressed: _openEditor,
                ),
                ShellVibeButton.secondary(
                  key: const Key('empty_import_runbook_button'),
                  label: 'Import',
                  icon: LucideIcons.fileUp,
                  onPressed: () => importRunbookMarkdown(
                    context,
                    ref,
                    workspaceId: _workspaceId,
                  ),
                ),
              ],
            ),
          );
        }

        final visible = _visibleRunbooks(runbooks);
        if (visible.isEmpty) {
          return layout(
            const ShellVibeEmptyState(
              icon: LucideIcons.searchX,
              title: 'No runbooks match your search.',
              description: 'Try another word from the title or description.',
            ),
          );
        }

        final selected = visible
            .where((runbook) => runbook.id == _selectedRunbookId)
            .firstOrNull;

        return layout(
          drawer: widget.showDetailDrawer && selected != null
              ? ShellVibeDetailDrawer(
                  child: _RunbookDetailPanel(
                    runbook: selected,
                    onRun: () => _executeRunbook(selected),
                    onEdit: () => _openEditor(runbook: selected),
                    onDelete: () => _deleteRunbook(selected),
                    onClose: () => setState(() => _selectedRunbookId = null),
                  ),
                )
              : null,
          Column(
            children: [
              AutomationListHeader(
                labels: const ['NAME', 'DESCRIPTION', 'STEPS'],
                columnFlex: _kRunbookColumnFlex,
                compact: widget.compact,
                actionCount: 1,
              ),
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
                      isExecuting: isRunning(runbook),
                      lastRun: lastRuns[runbook.id],
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
                      onExport: () =>
                          exportRunbookMarkdown(context, ref, runbook),
                      onDelete: () => _deleteRunbook(runbook),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<RunbookModel> _visibleRunbooks(List<RunbookModel> runbooks) {
    final tag = widget.selectedTag;
    final tagged = tag == null
        ? runbooks
        : runbooks.where((r) => r.tags.contains(tag)).toList();
    if (widget.searchQuery.isEmpty) return tagged;
    return tagged.where((runbook) {
      return runbook.title.toLowerCase().contains(widget.searchQuery) ||
          runbook.tags.any(
            (t) => t.toLowerCase().contains(widget.searchQuery),
          ) ||
          (runbook.description ?? '').toLowerCase().contains(
            widget.searchQuery,
          ) ||
          runbook.steps.any(
            (step) => step.command.toLowerCase().contains(widget.searchQuery),
          );
    }).toList();
  }

  void _showDetailSheet(RunbookModel runbook) => showAutomationDetailSheet(
    context,
    (sheetContext) => _RunbookDetailPanel(
      runbook: runbook,
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
  );

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
        variables: result.variables,
        tags: result.tags,
      );
    } else {
      await notifier.updateRunbook(result);
    }
  }

  Future<void> _deleteRunbook(RunbookModel runbook) async {
    if (!await confirmAutomationDelete(
      context,
      what: 'Runbook',
      name: runbook.title,
    )) {
      return;
    }
    if (!mounted) return;

    if (_selectedRunbookId == runbook.id) {
      setState(() => _selectedRunbookId = null);
    }
    await ref.read(runbooksProvider.notifier).deleteRunbook(runbook.id);
  }

  /// Target first, then variables: choosing where is the bigger decision, and
  /// nobody should type parameters for a run they then back out of. Cancelling
  /// either step starts nothing.
  Future<void> _executeRunbook(RunbookModel runbook) async {
    final notifier = ref.read(runbookRunProvider.notifier);
    if (notifier.isRunning) {
      _toastBusy();
      return;
    }

    final selection = await RunTargetSheet.show(
      context,
      subject: runbook.title,
      defaultHostIds: runbook.defaultHostIds,
      allowSaveDefault: true,
    );
    if (!mounted || selection == null) return;
    final hosts = selection.hosts;
    if (hosts.isEmpty) return;

    // Snippet steps count too: what they will run is what gets asked for.
    final snippets = {
      for (final s in await ref.read(snippetsProvider.future)) s.id: s,
    };
    if (!mounted) return;
    final needed = collectRunVariables(runbook, snippets: snippets);
    var variableValues = <String, String>{};
    if (!needed.isEmpty) {
      final inputs = await VariableInputDialog.show(
        context,
        variables: needed.names,
        declarations: needed.declarations,
        memoryKey: 'runbook:${runbook.id}',
        title: 'Runbook Input Parameters',
      );
      if (!mounted || inputs == null) return;
      variableValues = inputs;
    }

    if (!mounted) return;

    // The prompts above were awaited, so the answer to "is something running"
    // is read again before committing.
    if (notifier.isRunning) {
      _toastBusy();
      return;
    }

    // Saved once the run is certain to start, so backing out of the variables
    // dialog does not rewrite the runbook's defaults.
    if (selection.saveAsDefault) {
      await ref.read(runbooksProvider.notifier).setDefaultHostIds(runbook.id, [
        for (final host in hosts) host.id,
      ]);
      if (!mounted) return;
    }

    // The layout opens alongside the run, not after it: the run is a
    // background job and the tabs are there to be watched meanwhile.
    final layout = selection.openLayoutOf;
    if (layout != null) unawaited(openTemplateLayout(context, ref, layout));

    // Selecting the running runbook keeps its progress on screen.
    setState(() => _selectedRunbookId = runbook.id);
    // The run view opens at once rather than when the run ends: a run can
    // stop at an approval step, and the person who has to continue it needs to
    // see that while it is waiting.
    unawaited(
      notifier.start(
        runbook,
        hosts,
        variableValues: variableValues,
        strategy: selection.strategy,
      ),
    );
    await RunResultDialog.show(context);
  }

  void _toastBusy() => ShadToaster.of(
    context,
  ).show(const ShadToast(description: Text('A run is already in progress.')));
}

/// Single-line dense runbook row.
class _RunbookRow extends StatelessWidget {
  final RunbookModel runbook;
  final bool compact;
  final bool selected;
  final bool isExecuting;

  /// The runbook's most recent stored run, for the last-run badge.
  final RunHistorySummary? lastRun;
  final VoidCallback onSelect;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onExport;

  const _RunbookRow({
    super.key,
    required this.runbook,
    required this.compact,
    required this.selected,
    required this.isExecuting,
    this.lastRun,
    required this.onSelect,
    required this.onRun,
    required this.onEdit,
    required this.onDelete,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final stepCount = runbook.steps.length == 1
        ? '1 step'
        : '${runbook.steps.length} steps';
    // ✓ / ✗ and a time: the outcome is a glyph, not only a colour.
    final last = lastRun;
    final lastText = last == null
        ? null
        : '${last.status == 'succeeded' ? '✓' : '✗'} '
              '${relativeTime(last.finishedAt, DateTime.now())}';
    final stepLabel = lastText == null ? stepCount : '$stepCount · $lastText';
    final description = runbook.description?.isNotEmpty ?? false
        ? runbook.description!
        : null;

    return AutomationRow(
      tileKey: Key('runbook_tile_${runbook.id}'),
      title: runbook.title,
      // Compact drops the step column, so the count that would be lost moves
      // onto the description line.
      subtitle: compact
          ? [?description, stepLabel].join(' · ')
          : description ?? '—',
      third: Text(
        // Status is never carried by colour alone: the spinner is paired with
        // this text so the row still reads without it.
        isExecuting ? 'running' : stepLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: tokens.textMuted, fontSize: 12),
      ),
      columnFlex: _kRunbookColumnFlex,
      compact: compact,
      selected: selected,
      semanticsLabel: '${runbook.title}, runbook with $stepLabel',
      onSelect: onSelect,
      actions: [
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
      ],
      menuTooltip: 'Runbook actions',
      onMenuSelected: (value) {
        if (value == 'edit') onEdit();
        if (value == 'export') onExport();
        if (value == 'delete') onDelete();
      },
      menuItems: [
        automationMenuItem(
          value: 'edit',
          icon: LucideIcons.pencil,
          label: 'Edit runbook',
        ),
        automationMenuItem(
          key: const Key('runbook_menu_export'),
          value: 'export',
          icon: LucideIcons.fileDown,
          label: 'Export as Markdown',
        ),
        automationMenuItem(
          value: 'delete',
          icon: LucideIcons.trash2,
          label: 'Delete runbook',
          color: tokens.danger,
        ),
      ],
    );
  }
}

/// Inline right-hand detail panel for a runbook.
///
/// This is also where a run reports itself: the step list carries the live
/// per-step status instead of an expanding card in the list.
class _RunbookDetailPanel extends ConsumerWidget {
  final RunbookModel runbook;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  const _RunbookDetailPanel({
    required this.runbook,
    required this.onRun,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    // A run belongs to the runbook it started from; another runbook's panel
    // must not show it.
    final watched = ref.watch(runbookRunProvider);
    final run = watched?.runbook.id == runbook.id ? watched : null;
    final isExecuting = run?.running ?? false;

    return ListView(
      key: const Key('runbook_detail_drawer'),
      padding: const EdgeInsets.all(14),
      children: [
        AutomationDetailHeader(
          title: runbook.title,
          description: runbook.description,
          tags: runbook.tags,
          onClose: onClose,
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
          _RunbookStepTile(step: step, tokens: tokens),
        if (run != null) ...[
          const SizedBox(height: 8),
          const ShellVibeSectionLabel(label: 'Run', padding: EdgeInsets.zero),
          const SizedBox(height: 6),
          LiveRunView(run: run),
          const SizedBox(height: 6),
          ShellVibeButton.secondary(
            key: const Key('runbook_open_run'),
            label: 'Open run view',
            icon: LucideIcons.layoutGrid,
            onPressed: () => RunResultDialog.show(context),
            expand: true,
          ),
        ],
        const SizedBox(height: 8),
        RunbookHistorySection(runbook: runbook),
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

/// A step as defined; the live run below the list is where its status shows.
class _RunbookStepTile extends StatelessWidget {
  final RunbookStepModel step;
  final ShellVibeTokens tokens;

  const _RunbookStepTile({required this.step, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.circle, size: 14, color: tokens.textMuted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (step.kind == StepKind.approval)
                  Row(
                    children: [
                      Icon(
                        LucideIcons.userCheck,
                        size: 13,
                        color: tokens.warning,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Approval: ${step.command}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    step.command,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                if (step.expectedOutputPattern?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  ShellVibeStatusChip(
                    label: 'expects ${step.expectedOutputPattern}',
                  ),
                ],
                if (step.onFailure == StepFailurePolicy.continueRun ||
                    step.retries > 0) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (step.onFailure == StepFailurePolicy.continueRun)
                        const ShellVibeStatusChip(
                          label: 'continues on failure',
                        ),
                      if (step.retries > 0)
                        ShellVibeStatusChip(
                          label:
                              '${step.retries} ${step.retries == 1 ? 'retry' : 'retries'}',
                        ),
                    ],
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
