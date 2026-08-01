import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/runbook_model.dart';
import '../../domain/models/runbook_step_model.dart';

/// Form dialog for creating or editing a Runbook and its step sequence.
class RunbookEditorDialog extends StatefulWidget {
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
      builder: (context) => RunbookEditorDialog(
        runbook: runbook,
        workspaceId: workspaceId,
      ),
    );
  }

  @override
  State<RunbookEditorDialog> createState() => _RunbookEditorDialogState();
}

class _RunbookEditorDialogState extends State<RunbookEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  final List<RunbookStepModel> _steps = [];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.runbook?.title ?? '');
    _descriptionController = TextEditingController(text: widget.runbook?.description ?? '');
    if (widget.runbook != null) {
      _steps.addAll(widget.runbook!.steps);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _addStep() {
    setState(() {
      _steps.add(RunbookStepModel(
        id: const Uuid().v4(),
        runbookId: widget.runbook?.id ?? '',
        stepOrder: _steps.length + 1,
        command: '',
        expectedExitCode: 0,
        timeoutSeconds: 30,
      ));
    });
  }

  void _removeStep(int index) {
    setState(() {
      _steps.removeAt(index);
      for (int i = 0; i < _steps.length; i++) {
        _steps[i] = _steps[i].copyWith(stepOrder: i + 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.runbook != null;

    return ShadDialog(
      title: Text(isEditing ? 'Edit Runbook' : 'New Runbook'),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ShadButton(
          key: const Key('runbook_save_button'),
          onPressed: () {
            if (_steps.isEmpty) {
              ShadToaster.of(context).show(
                const ShadToast.destructive(
                  title: Text('Validation Error'),
                  description: Text('Runbook must have at least 1 step.'),
                ),
              );
              return;
            }
            if (_formKey.currentState!.validate()) {
              final result = RunbookModel(
                id: widget.runbook?.id ?? const Uuid().v4(),
                workspaceId: widget.workspaceId,
                title: _titleController.text.trim(),
                description: _descriptionController.text.trim().isEmpty
                    ? null
                    : _descriptionController.text.trim(),
                steps: _steps,
                createdAt: widget.runbook?.createdAt ?? DateTime.now(),
              );
              Navigator.of(context).pop(result);
            }
          },
          child: Text(isEditing ? 'Save' : 'Create'),
        ),
      ],
      child: SizedBox(
        width: 550,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShadInputFormField(
                  key: const Key('runbook_title_field'),
                  controller: _titleController,
                  label: const Text('Runbook Title'),
                  placeholder: const Text('e.g. Deploy Microservices Pipeline'),
                  validator: (val) => val.trim().isEmpty ? 'Title is required' : null,
                ),
                const SizedBox(height: 12),
                ShadInputFormField(
                  key: const Key('runbook_desc_field'),
                  controller: _descriptionController,
                  label: const Text('Description (optional)'),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Steps (${_steps.length})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    ShadButton(
                      key: const Key('runbook_add_step_button'),
                      onPressed: _addStep,
                      leading: const Icon(Icons.add, size: 16),
                      child: const Text('Add Step'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_steps.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text('No steps added yet. Click "Add Step" to define commands.'),
                    ),
                  ),
                ..._steps.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final step = entry.value;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Step ${idx + 1}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              ShadIconButton.ghost(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                                onPressed: () => _removeStep(idx),
                              ),
                            ],
                          ),
                          ShadInputFormField(
                            key: ValueKey('step_command_${step.id}'),
                            initialValue: step.command,
                            label: const Text('Command'),
                            placeholder: const Text('docker-compose pull'),
                            validator: (val) => val.trim().isEmpty ? 'Command required' : null,
                            onChanged: (val) {
                              // Read the live element: `step` is the build-time
                              // snapshot, so copying from it would silently
                              // revert edits made to the other fields.
                              _steps[idx] = _steps[idx].copyWith(command: val);
                            },
                          ),
                          const SizedBox(height: 8),
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
                                      _steps[idx] =
                                          _steps[idx].copyWith(expectedExitCode: code);
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
                                  onChanged: (val) {
                                    _steps[idx] = _steps[idx].copyWith(
                                      expectedOutputPattern: val.isEmpty ? null : val,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

