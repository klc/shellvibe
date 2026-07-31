import 'package:flutter/material.dart';
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

    return AlertDialog(
      title: Text(isEditing ? 'Edit Runbook' : 'New Runbook'),
      content: SizedBox(
        width: 550,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: const Key('runbook_title_field'),
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Runbook Title',
                    hintText: 'e.g. Deploy Microservices Pipeline',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Title is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('runbook_desc_field'),
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Steps (${_steps.length})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton.icon(
                      key: const Key('runbook_add_step_button'),
                      onPressed: _addStep,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Step'),
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
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                onPressed: () => _removeStep(idx),
                              ),
                            ],
                          ),
                          TextFormField(
                            key: Key('step_command_$idx'),
                            initialValue: step.command,
                            decoration: const InputDecoration(
                              labelText: 'Command',
                              hintText: 'docker-compose pull',
                              border: OutlineInputBorder(),
                            ),
                            validator: (val) =>
                                val == null || val.trim().isEmpty ? 'Command required' : null,
                            onChanged: (val) {
                              _steps[idx] = step.copyWith(command: val);
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  key: Key('step_exit_code_$idx'),
                                  initialValue: step.expectedExitCode.toString(),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Exit Code',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (val) {
                                    final code = int.tryParse(val) ?? 0;
                                    _steps[idx] = step.copyWith(expectedExitCode: code);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  key: Key('step_pattern_$idx'),
                                  initialValue: step.expectedOutputPattern ?? '',
                                  decoration: const InputDecoration(
                                    labelText: 'Output Regex / String',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (val) {
                                    _steps[idx] = step.copyWith(
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('runbook_save_button'),
          onPressed: () {
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
    );
  }
}
