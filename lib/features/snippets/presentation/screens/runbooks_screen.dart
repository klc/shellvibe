import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../domain/models/runbook_model.dart';
import '../../domain/models/runbook_step_model.dart';
import '../../domain/services/runbook_executor.dart';
import '../../domain/services/snippet_variable_parser.dart';
import '../notifiers/runbooks_notifier.dart';
import '../widgets/runbook_editor_dialog.dart';
import '../widgets/variable_input_dialog.dart';

class RunbooksScreen extends ConsumerStatefulWidget {
  final String workspaceId;
  final Future<(String output, int exitCode)> Function(String command, int timeoutSeconds)?
      customCommandRunner;

  const RunbooksScreen({
    super.key,
    this.workspaceId = 'default',
    this.customCommandRunner,
  });

  @override
  ConsumerState<RunbooksScreen> createState() => _RunbooksScreenState();
}

class _RunbooksScreenState extends ConsumerState<RunbooksScreen> {
  final Map<String, String> _stepStatuses = {};
  bool _isExecuting = false;
  String? _executingRunbookId;

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
      _stepStatuses.clear();
    });

    final commandRunner = widget.customCommandRunner ??
        (String command, int timeoutSeconds) async {
          // Default fallback runner simulation if no active terminal runner passed
          await Future.delayed(const Duration(milliseconds: 500));
          return ('Executed: $command\nStatus: OK', 0);
        };

    final result = await ref.read(runbooksProvider.notifier).executeRunbook(
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
    showDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: Row(
          children: [
            Icon(
              result.overallSuccess ? Icons.check_circle : Icons.error,
              color: result.overallSuccess ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(result.overallSuccess ? 'Runbook Succeeded' : 'Runbook Failed'),
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
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: sr.success ? Colors.green : Colors.red,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Step ${sr.step.stepOrder}: ${sr.step.command}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text('Status: ${sr.success ? "SUCCESS" : "FAILED"}'),
                        if (sr.output.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            sr.output,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                          ),
                        ],
                        if (sr.errorMessage != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            sr.errorMessage!,
                            style: const TextStyle(color: Colors.red, fontSize: 11),
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
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final runbooksAsync = ref.watch(runbooksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Executable Runbooks'),
        actions: [
          IconButton(
            key: const Key('add_runbook_button'),
            icon: const Icon(Icons.add),
            tooltip: 'New Runbook',
            onPressed: () async {
              final newRunbook = await RunbookEditorDialog.show(
                context,
                workspaceId: widget.workspaceId,
              );
              if (newRunbook != null) {
                ref.read(runbooksProvider.notifier).addRunbook(
                      workspaceId: newRunbook.workspaceId,
                      title: newRunbook.title,
                      description: newRunbook.description,
                      steps: newRunbook.steps,
                    );
              }
            },
          ),
        ],
      ),
      body: runbooksAsync.when(
        data: (runbooks) {
          if (runbooks.isEmpty) {
            return const Center(
              child: Text('No runbooks defined. Click "+" to create a multi-step runbook.'),
            );
          }

          return ListView.builder(
            itemCount: runbooks.length,
            itemBuilder: (context, index) {
              final runbook = runbooks[index];
              final isThisExecuting = _isExecuting && _executingRunbookId == runbook.id;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ShadCard(
                  child: ExpansionTile(
                    key: Key('runbook_tile_${runbook.id}'),
                    title: Text(
                      runbook.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Text(
                      '${runbook.steps.length} Steps ${runbook.description != null ? "• ${runbook.description}" : ""}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShadButton(
                          key: Key('runbook_execute_${runbook.id}'),
                          onPressed: isThisExecuting ? null : () => _executeRunbook(runbook),
                          leading: isThisExecuting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.play_arrow, color: Colors.green, size: 16),
                          child: Text(isThisExecuting ? 'Running...' : 'Run'),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          onSelected: (val) async {
                            if (val == 'edit') {
                              final updated = await RunbookEditorDialog.show(
                                context,
                                runbook: runbook,
                                workspaceId: widget.workspaceId,
                              );
                              if (updated != null) {
                                ref
                                    .read(runbooksProvider.notifier)
                                    .updateRunbook(updated);
                              }
                            } else if (val == 'delete') {
                              ref
                                  .read(runbooksProvider.notifier)
                                  .deleteRunbook(runbook.id);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'edit', child: Text('Edit')),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    children: [
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: runbook.steps.map((step) {
                            final status = _stepStatuses[step.id];
                            Color statusColor = Colors.grey;
                            IconData statusIcon = Icons.arrow_right;

                            if (status == 'running') {
                              statusColor = Colors.orange;
                              statusIcon = Icons.hourglass_top;
                            } else if (status == 'success') {
                              statusColor = Colors.green;
                              statusIcon = Icons.check_circle;
                            } else if (status == 'failed') {
                              statusColor = Colors.red;
                              statusIcon = Icons.cancel;
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: Row(
                                children: [
                                  Icon(statusIcon, color: statusColor, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Step ${step.stepOrder}:',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      step.command,
                                      style: const TextStyle(fontFamily: 'monospace'),
                                    ),
                                  ),
                                  if (step.expectedOutputPattern != null)
                                    ShadBadge.secondary(
                                      child: Text(
                                        'Pattern: ${step.expectedOutputPattern}',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error loading runbooks: $err')),
      ),
    );
  }
}
