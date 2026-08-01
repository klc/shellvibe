import 'dart:async';

import '../models/runbook_model.dart';
import '../models/runbook_step_model.dart';
import 'snippet_variable_parser.dart';

/// Result of executing a single runbook step.
class RunbookStepResult {
  final RunbookStepModel step;
  final bool success;
  final int? exitCode;
  final String output;
  final String? errorMessage;

  const RunbookStepResult({
    required this.step,
    required this.success,
    this.exitCode,
    required this.output,
    this.errorMessage,
  });
}

/// Overall execution result for a runbook run.
class RunbookExecutionResult {
  final String runbookId;
  final bool overallSuccess;
  final List<RunbookStepResult> stepResults;
  final RunbookStepModel? failedStep;

  const RunbookExecutionResult({
    required this.runbookId,
    required this.overallSuccess,
    required this.stepResults,
    this.failedStep,
  });
}

/// Execution engine for multi-step automation scripts across terminal sessions.
class RunbookExecutor {
  /// Executes a [runbook] sequentially using [commandRunner].
  ///
  /// [commandRunner] is a callback receiving the command string and returning
  /// a record of the combined stdout/stderr output and the process exit code,
  /// so [RunbookStepModel.expectedExitCode] can be enforced for real.
  /// [variableValues] optional map of variable inputs to substitute into command templates.
  /// [onProgress] optional callback invoked before each step starts.
  Future<RunbookExecutionResult> executeRunbook(
    RunbookModel runbook,
    Future<(String output, int exitCode)> Function(String command, int timeoutSeconds)
        commandRunner, {
    Map<String, String> variableValues = const {},
    void Function(RunbookStepModel step, String status)? onProgress,
  }) async {
    final results = <RunbookStepResult>[];

    // Sort steps by stepOrder
    final sortedSteps = List<RunbookStepModel>.from(runbook.steps)
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));

    for (final step in sortedSteps) {
      if (onProgress != null) {
        onProgress(step, 'running');
      }

      // Substitute variables in command
      final commandToRun = SnippetVariableParser.substituteVariables(step.command, variableValues);

      try {
        final (output, exitCode) = await commandRunner(commandToRun, step.timeoutSeconds);

        // Check output verification pattern if specified
        bool patternMatches = true;
        if (step.expectedOutputPattern != null && step.expectedOutputPattern!.isNotEmpty) {
          try {
            final regex = RegExp(step.expectedOutputPattern!);
            patternMatches = regex.hasMatch(output);
          } catch (_) {
            patternMatches = output.contains(step.expectedOutputPattern!);
          }
        }

        final exitCodeMatches = exitCode == step.expectedExitCode;
        final stepSuccess = patternMatches && exitCodeMatches;
        final stepResult = RunbookStepResult(
          step: step,
          success: stepSuccess,
          exitCode: exitCode,
          output: output,
          errorMessage: stepSuccess
              ? null
              : (exitCodeMatches
                  ? 'Output verification failed for pattern: "${step.expectedOutputPattern}"'
                  : 'Exit code $exitCode does not match expected ${step.expectedExitCode}'),
        );

        results.add(stepResult);

        if (!stepSuccess) {
          if (onProgress != null) onProgress(step, 'failed');
          return RunbookExecutionResult(
            runbookId: runbook.id,
            overallSuccess: false,
            stepResults: results,
            failedStep: step,
          );
        }

        if (onProgress != null) onProgress(step, 'success');
      } catch (e) {
        final stepResult = RunbookStepResult(
          step: step,
          success: false,
          output: '',
          errorMessage: e.toString(),
        );
        results.add(stepResult);
        if (onProgress != null) onProgress(step, 'failed');

        return RunbookExecutionResult(
          runbookId: runbook.id,
          overallSuccess: false,
          stepResults: results,
          failedStep: step,
        );
      }
    }

    return RunbookExecutionResult(
      runbookId: runbook.id,
      overallSuccess: true,
      stepResults: results,
    );
  }
}
