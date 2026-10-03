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

  /// True when the run was stopped by the caller. Distinct from a failure:
  /// [failedStep] is null and the steps that never ran were reported
  /// `cancelled`, not `failed`.
  final bool cancelled;

  const RunbookExecutionResult({
    required this.runbookId,
    required this.overallSuccess,
    required this.stepResults,
    this.failedStep,
    this.cancelled = false,
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
  /// [isCancelled] is polled before each step and again once a step's runner
  /// returns or throws; once true the in-flight step and every later one are
  /// reported `cancelled` and the run ends. It cannot stop a runner by itself —
  /// the caller interrupts that.
  Future<RunbookExecutionResult> executeRunbook(
    RunbookModel runbook,
    Future<(String output, int exitCode)> Function(String command, int timeoutSeconds)
        commandRunner, {
    Map<String, String> variableValues = const {},
    void Function(RunbookStepModel step, String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final results = <RunbookStepResult>[];

    // Sort steps by stepOrder
    final sortedSteps = List<RunbookStepModel>.from(runbook.steps)
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));

    RunbookExecutionResult cancelledFrom(int index) {
      for (final rest in sortedSteps.skip(index)) {
        onProgress?.call(rest, 'cancelled');
      }
      return RunbookExecutionResult(
        runbookId: runbook.id,
        overallSuccess: false,
        stepResults: results,
        cancelled: true,
      );
    }

    for (var i = 0; i < sortedSteps.length; i++) {
      final step = sortedSteps[i];
      if (isCancelled?.call() ?? false) return cancelledFrom(i);
      if (onProgress != null) {
        onProgress(step, 'running');
      }

      // Substitute variables in command
      final commandToRun = SnippetVariableParser.substituteVariables(step.command, variableValues);

      try {
        final (output, exitCode) = await commandRunner(commandToRun, step.timeoutSeconds);
        if (isCancelled?.call() ?? false) return cancelledFrom(i);

        // Check output verification pattern if specified
        bool patternMatches = true;
        String? patternError;
        if (step.expectedOutputPattern != null && step.expectedOutputPattern!.isNotEmpty) {
          try {
            final regex = RegExp(step.expectedOutputPattern!);
            patternMatches = regex.hasMatch(output);
          } catch (e) {
            patternMatches = false;
            patternError = 'Invalid regex pattern "${step.expectedOutputPattern}": $e';
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
              : (patternError ??
                  (exitCodeMatches
                      ? 'Output verification failed for pattern: "${step.expectedOutputPattern}"'
                      : 'Exit code $exitCode does not match expected ${step.expectedExitCode}')),
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
        if (isCancelled?.call() ?? false) return cancelledFrom(i);
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
