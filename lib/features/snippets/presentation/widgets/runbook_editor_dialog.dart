import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/app/widgets/shellvibe_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../domain/models/runbook_model.dart';
import '../../domain/models/runbook_step_model.dart';
import '../../domain/models/snippet_model.dart';
import '../../domain/models/variable_declaration.dart';
import '../../domain/services/run_variables.dart';
import '../notifiers/snippets_notifier.dart';
import 'variables_editor.dart';

/// Form dialog for creating or editing a Runbook and its step sequence.
class RunbookEditorDialog extends ConsumerStatefulWidget {
  final RunbookModel? runbook;
  final String workspaceId;

  const RunbookEditorDialog({
    super.key,
    this.runbook,
    required this.workspaceId,
  });

  static Future<RunbookModel?> show(
    BuildContext context, {
    RunbookModel? runbook,
    required String workspaceId,
  }) {
    return showDialog<RunbookModel>(
      context: context,
      builder: (context) =>
          RunbookEditorDialog(runbook: runbook, workspaceId: workspaceId),
    );
  }

  @override
  ConsumerState<RunbookEditorDialog> createState() =>
      _RunbookEditorDialogState();
}

class _RunbookEditorDialogState extends ConsumerState<RunbookEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  final List<RunbookStepModel> _steps = [];
  List<VariableDeclaration> _declarations = const [];

  /// Set by a save attempt with no steps, so the message sits by the list it
  /// is about rather than in a separate alert.
  bool _noStepsError = false;

  /// The snippets, by id, for snippet steps; empty until they load.
  Map<String, SnippetModel> get _snippets => {
    for (final s in ref.read(snippetsProvider).value ?? const <SnippetModel>[])
      s.id: s,
  };

  /// The `${INPUT:...}` names the steps will ask for: from commands as typed
  /// and, for snippet steps, from the snippet's code.
  List<String> _usedVariableNames() => collectRunVariables(
    RunbookModel(
      id: '',
      workspaceId: widget.workspaceId,
      title: '',
      createdAt: DateTime(2026),
      steps: _steps,
    ),
    snippets: _snippets,
  ).names;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.runbook?.title ?? '');
    _descriptionController = TextEditingController(
      text: widget.runbook?.description ?? '',
    );
    if (widget.runbook != null) {
      _steps.addAll(widget.runbook!.steps);
      _declarations = widget.runbook!.variables;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  RunbookStepModel _newStep({StepKind kind = StepKind.command}) =>
      RunbookStepModel(
        id: const Uuid().v4(),
        runbookId: widget.runbook?.id ?? '',
        stepOrder: _steps.length + 1,
        command: '',
        expectedExitCode: 0,
        timeoutSeconds: 30,
        kind: kind,
      );

  void _renumber() {
    for (var i = 0; i < _steps.length; i++) {
      _steps[i] = _steps[i].copyWith(stepOrder: i + 1);
    }
  }

  void _addStep() => setState(() {
    _steps.add(_newStep());
    _noStepsError = false;
  });

  void _removeStep(int index) => setState(() {
    _steps.removeAt(index);
    _renumber();
  });

  void _duplicateStep(int index) => setState(() {
    _steps.insert(index + 1, _steps[index].copyWith(id: const Uuid().v4()));
    _renumber();
  });

  void _moveStep(int from, int to) {
    if (to < 0 || to >= _steps.length || from == to) return;
    setState(() {
      _steps.insert(to, _steps.removeAt(from));
      _renumber();
    });
  }

  /// A step as the editor keeps it: [change] applied to the live element, never
  /// to a build-time copy, so editing one field cannot revert another.
  void _update(int index, RunbookStepModel Function(RunbookStepModel) change) {
    _steps[index] = change(_steps[index]);
  }

  Future<void> _pickSnippet(int index) async {
    final picked = await showAdaptivePanel<SnippetModel>(
      context: context,
      title: 'Choose a snippet',
      desktopHeight: 460,
      isScrollControlled: true,
      builder: (ctx) => _SnippetPicker(
        snippets: ref.read(snippetsProvider).value ?? const [],
        onPicked: (snippet) => Navigator.of(ctx).pop(snippet),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _update(
        index,
        // The command column keeps a comment naming the snippet: a client that
        // predates snippet steps then runs a no-op rather than an empty line.
        (s) => s.copyWith(
          kind: StepKind.snippet,
          snippetId: picked.id,
          command: '# snippet: ${picked.title}',
        ),
      );
    });
  }

  void _setKind(int index, StepKind kind) {
    if (_steps[index].kind == kind) return;
    setState(() {
      _update(index, (s) {
        final isPlaceholder = s.command.startsWith('# snippet: ');
        return s.copyWith(
          kind: kind,
          // What the old kind kept in `command` means nothing to the new one.
          command: kind == StepKind.snippet || isPlaceholder ? '' : s.command,
          clearSnippet: kind != StepKind.snippet,
        );
      });
    });
  }

  void _save() {
    if (_steps.isEmpty) {
      setState(() => _noStepsError = true);
      return;
    }
    // A snippet step with no snippet would run nothing, and a gate with no
    // message says nothing.
    final invalid = _steps.any(
      (s) => switch (s.kind) {
        StepKind.command => s.command.trim().isEmpty,
        StepKind.snippet => s.snippetId == null,
        StepKind.approval => s.command.trim().isEmpty,
      },
    );
    final formOk = _formKey.currentState!.validate();
    if (invalid || !formOk) {
      setState(() {});
      return;
    }
    final result = RunbookModel(
      id: widget.runbook?.id ?? const Uuid().v4(),
      workspaceId: widget.workspaceId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      steps: _steps,
      createdAt: widget.runbook?.createdAt ?? DateTime.now(),
      // Not edited here: the target sheet owns the default hosts.
      defaultHostIds: widget.runbook?.defaultHostIds ?? const [],
      tags: widget.runbook?.tags ?? const [],
      // Only for placeholders still in a step.
      variables: VariablesEditor.declarationsToSave(
        _usedVariableNames(),
        _declarations,
      ),
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.runbook != null;
    final tokens = ShellVibeTokens.resolve(context);
    // Watched, so a snippet step shows its code once the snippets have loaded.
    ref.watch(snippetsProvider);

    return ShadDialog(
      // Asked for as a constraint, not as a width on the child: shadcn caps the
      // dialog at 512px, so a wider SizedBox inside it was silently clamped and
      // the step list never got the room it was written for.
      constraints: const BoxConstraints(maxWidth: 560),
      title: Text(isEditing ? 'Edit Runbook' : 'New Runbook'),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(null),
        ),
        ShellVibeButton(
          key: const Key('runbook_save_button'),
          label: isEditing ? 'Save' : 'Create',
          onPressed: _save,
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
      // Its own Material: the chips, dropdowns and reorderable list below are
      // Material widgets and a ShadDialog paints none.
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  ShadInputFormField(
                    key: const Key('runbook_title_field'),
                    controller: _titleController,
                    label: const Text('Runbook Title'),
                    placeholder: const Text(
                      'e.g. Deploy Microservices Pipeline',
                    ),
                    validator: (val) =>
                        val.trim().isEmpty ? 'Title is required' : null,
                  ),
                  const SizedBox(height: 12),
                  ShadInputFormField(
                    key: const Key('runbook_desc_field'),
                    controller: _descriptionController,
                    label: const Text('Description (optional)'),
                  ),
                  const SizedBox(height: 16),
                  ShellVibeFormSectionHeader(
                    icon: LucideIcons.listOrdered,
                    title: 'Steps (${_steps.length})',
                    trailing: ShellVibeButton(
                      key: const Key('runbook_add_step_button'),
                      label: 'Add Step',
                      icon: Icons.add,
                      onPressed: _addStep,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_steps.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          _noStepsError
                              ? 'Runbook must have at least 1 step.'
                              : 'No steps added yet. Click "Add Step" to '
                                    'define commands.',
                          key: const Key('runbook_steps_error'),
                          style: TextStyle(
                            color: _noStepsError ? tokens.danger : null,
                          ),
                        ),
                      ),
                    ),
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    onReorderItem: _moveStep,
                    children: [
                      for (var i = 0; i < _steps.length; i++)
                        _stepCard(i, tokens),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const PlaceholderHelp(),
                  const SizedBox(height: 12),
                  const ShellVibeFormSectionHeader(
                    icon: LucideIcons.variable,
                    title: 'Variables',
                  ),
                  const SizedBox(height: 4),
                  VariablesEditor(
                    names: _usedVariableNames(),
                    declarations: _declarations,
                    onChanged: (next) => setState(
                      () => _declarations = VariablesEditor.merge(
                        _declarations,
                        next,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kindChip(int index, StepKind kind, String label) {
    final step = _steps[index];
    final selected = step.kind == kind;
    final tokens = ShellVibeTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        key: Key('step_kind_${step.id}_${kind.name}'),
        onTap: () => _setKind(index, kind),
        borderRadius: BorderRadius.circular(tokens.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? tokens.brand.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(tokens.radiusPill),
            border: Border.all(
              color: selected
                  ? tokens.brand.withValues(alpha: 0.34)
                  : tokens.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: selected ? tokens.brand : tokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepCard(int idx, ShellVibeTokens tokens) {
    final step = _steps[idx];
    final snippet = _snippets[step.snippetId];
    // Shown once the user has tried to save, not while they are still typing.
    return Card(
      key: ValueKey('step_card_${step.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: idx,
                  child: Tooltip(
                    message: 'Drag to reorder',
                    child: Icon(
                      LucideIcons.gripVertical,
                      key: Key('step_drag_${step.id}'),
                      size: 16,
                      color: tokens.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Step ${idx + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                // The keyboard route to what dragging does.
                ShellVibeIconButton(
                  key: Key('step_up_${step.id}'),
                  icon: LucideIcons.arrowUp,
                  tooltip: 'Move step up',
                  onPressed: idx == 0 ? null : () => _moveStep(idx, idx - 1),
                ),
                ShellVibeIconButton(
                  key: Key('step_down_${step.id}'),
                  icon: LucideIcons.arrowDown,
                  tooltip: 'Move step down',
                  onPressed: idx == _steps.length - 1
                      ? null
                      : () => _moveStep(idx, idx + 1),
                ),
                ShellVibeIconButton(
                  key: Key('step_duplicate_${step.id}'),
                  icon: LucideIcons.copy,
                  tooltip: 'Duplicate step',
                  onPressed: () => _duplicateStep(idx),
                ),
                ShellVibeIconButton(
                  key: Key('step_remove_${step.id}'),
                  icon: LucideIcons.trash2,
                  tooltip: 'Remove step',
                  danger: true,
                  onPressed: () => _removeStep(idx),
                ),
              ],
            ),
            Row(
              children: [
                _kindChip(idx, StepKind.command, 'Command'),
                _kindChip(idx, StepKind.snippet, 'Snippet'),
                _kindChip(idx, StepKind.approval, 'Approval'),
              ],
            ),
            const SizedBox(height: 8),
            switch (step.kind) {
              StepKind.command => ShadInputFormField(
                key: ValueKey('step_command_${step.id}'),
                initialValue: step.command,
                label: const Text('Command'),
                placeholder: const Text('docker-compose pull'),
                validator: (val) =>
                    val.trim().isEmpty ? 'Command required' : null,
                onChanged: (val) {
                  // Rebuilt so the Variables section follows what is typed.
                  setState(() => _update(idx, (s) => s.copyWith(command: val)));
                },
              ),
              StepKind.approval => ShadInputFormField(
                key: ValueKey('step_message_${step.id}'),
                initialValue: step.command,
                label: const Text('Message'),
                placeholder: const Text('Check the dashboards, then continue'),
                validator: (val) =>
                    val.trim().isEmpty ? 'A message is required' : null,
                onChanged: (val) =>
                    _update(idx, (s) => s.copyWith(command: val)),
              ),
              StepKind.snippet => _snippetSection(idx, step, snippet, tokens),
            },
            if (step.kind != StepKind.approval) ...[
              const SizedBox(height: 8),
              _policyFields(idx, step),
            ],
          ],
        ),
      ),
    );
  }

  Widget _snippetSection(
    int idx,
    RunbookStepModel step,
    SnippetModel? snippet,
    ShellVibeTokens tokens,
  ) {
    final missing = step.snippetId != null && snippet == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShellVibeButton.secondary(
          key: Key('step_snippet_pick_${step.id}'),
          label: snippet != null
              ? 'Snippet: ${snippet.title}'
              : 'Choose a snippet…',
          icon: LucideIcons.search,
          onPressed: () => _pickSnippet(idx),
        ),
        if (step.snippetId == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Choose the snippet this step runs.',
              key: Key('step_snippet_hint_${step.id}'),
              style: TextStyle(color: tokens.danger, fontSize: 11),
            ),
          ),
        if (missing)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'This snippet no longer exists.',
              style: TextStyle(color: tokens.danger, fontSize: 11),
            ),
          ),
        if (snippet != null)
          Container(
            key: Key('step_snippet_code_${step.id}'),
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tokens.canvas,
              borderRadius: BorderRadius.circular(tokens.radiusSmall),
              border: Border.all(color: tokens.border),
            ),
            // Read-only: the snippet is edited in the snippet library, and a
            // run always uses it as it is then.
            child: SelectableText(
              snippet.code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _policyFields(int idx, RunbookStepModel step) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ShadInputFormField(
                key: ValueKey('step_exit_code_${step.id}'),
                initialValue: step.expectedExitCode.toString(),
                keyboardType: TextInputType.number,
                label: const Text('Exit Code'),
                validator: (val) {
                  if (val.trim().isEmpty) return 'Required';
                  if (int.tryParse(val.trim()) == null) {
                    return 'Must be a valid integer';
                  }
                  return null;
                },
                onChanged: (val) {
                  final code = int.tryParse(val.trim());
                  if (code != null) {
                    _update(idx, (s) => s.copyWith(expectedExitCode: code));
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ShadInputFormField(
                key: ValueKey('step_pattern_${step.id}'),
                initialValue: step.expectedOutputPattern ?? '',
                label: const Text('Output Regex / String'),
                validator: (val) {
                  if (val.isEmpty) return null;
                  try {
                    RegExp(val);
                    return null;
                  } catch (_) {
                    return 'Invalid regex pattern';
                  }
                },
                onChanged: (val) => _update(
                  idx,
                  (s) => s.copyWith(
                    expectedOutputPattern: val.isEmpty ? null : val,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<StepFailurePolicy>(
                key: ValueKey('step_on_failure_${step.id}'),
                initialValue: step.onFailure,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'On failure',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: StepFailurePolicy.stop,
                    child: Text('Stop'),
                  ),
                  DropdownMenuItem(
                    value: StepFailurePolicy.continueRun,
                    child: Text('Continue'),
                  ),
                ],
                onChanged: (val) {
                  if (val == null) return;
                  setState(
                    () => _update(idx, (s) => s.copyWith(onFailure: val)),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ShadInputFormField(
                key: ValueKey('step_retries_${step.id}'),
                initialValue: step.retries.toString(),
                keyboardType: TextInputType.number,
                label: const Text('Retries (0-5)'),
                validator: (val) {
                  final n = int.tryParse(val.trim());
                  if (n == null || n < 0 || n > RunbookStepModel.maxRetries) {
                    return '0 to ${RunbookStepModel.maxRetries}';
                  }
                  return null;
                },
                onChanged: (val) {
                  final n = int.tryParse(val.trim());
                  if (n != null && n >= 0 && n <= RunbookStepModel.maxRetries) {
                    _update(idx, (s) => s.copyWith(retries: n));
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A searchable list of the snippets a step can run.
class _SnippetPicker extends StatefulWidget {
  final List<SnippetModel> snippets;
  final ValueChanged<SnippetModel> onPicked;

  const _SnippetPicker({required this.snippets, required this.onPicked});

  @override
  State<_SnippetPicker> createState() => _SnippetPickerState();
}

class _SnippetPickerState extends State<_SnippetPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final visible = [
      for (final s in widget.snippets)
        if (needle.isEmpty ||
            s.title.toLowerCase().contains(needle) ||
            s.code.toLowerCase().contains(needle) ||
            s.tags.any((t) => t.toLowerCase().contains(needle)))
          s,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: ShellVibeSearchField(
            fieldKey: const Key('step_snippet_search'),
            hintText: 'Search snippets…',
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Flexible(
          child: visible.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No snippets match.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final snippet in visible)
                      ListTile(
                        key: Key('step_snippet_option_${snippet.id}'),
                        dense: true,
                        title: Text(snippet.title),
                        subtitle: Text(
                          snippet.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        onTap: () => widget.onPicked(snippet),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
