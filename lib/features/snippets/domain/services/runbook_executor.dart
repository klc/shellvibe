import 'dart:async';

import '../models/runbook_model.dart';
import '../models/runbook_step_model.dart';
import 'snippet_variable_parser.dart';

/// One try at a step. A step with retries keeps one per attempt.
class StepAttempt {
  final bool success;
  final int? exitCode;
  final String output;
  final String? errorMessage;

  const StepAttempt({
    required this.success,
    this.exitCode,
    required this.output,
    this.errorMessage,
  });
}

/// Result of executing a single runbook step.
///
/// The top-level fields are those of the last attempt, which is the one that
/// decided the step; [attemptLog] keeps every attempt.
class RunbookStepResult {
  final RunbookStepModel step;
  final bool success;
  final int? exitCode;
  final String output;
  final String? errorMessage;

  /// The command as sent, after `${INPUT:...}` substitution.
  final String command;

  /// Attempts made: 1 plus the retries that were used.
  final int attempts;
  final List<StepAttempt> attemptLog;

  /// Wall time across every attempt and the waits between them.
  final int? durationMs;

  /// Only the tail of the output was kept (history storage caps it).
  final bool outputTruncated;

  const RunbookStepResult({
    required this.step,
    required this.success,
    this.exitCode,
    required this.output,
    this.errorMessage,
    this.command = '',
    this.attempts = 1,
    this.attemptLog = const [],
    this.durationMs,
    this.outputTruncated = false,
  });
}

/// Overall execution result for a runbook run.
class RunbookExecutionResult {
  final String runbookId;
  final bool overallSuccess;
  final List<RunbookStepResult> stepResults;

  /// The first step that failed, whether or not the run went on past it.
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
  /// Pause between attempts of a step with retries. Fixed and short: it is a
  /// breath for a service that is restarting, not a back-off policy.
  final Duration retryDelay;

  const RunbookExecutor({this.retryDelay = const Duration(seconds: 2)});

  /// Executes a [runbook] sequentially using [commandRunner].
  ///
  /// [commandRunner] is a callback receiving the command string and returning
  /// a record of the combined stdout/stderr output and the process exit code,
  /// so [RunbookStepModel.expectedExitCode] can be enforced for real.
  /// [variableValues] optional map of variable inputs to substitute into command templates.
  /// [onProgress] optional callback invoked before each step starts.
  /// [onStepFinished] is called with a step's result as soon as it settles
  /// (success or failure, after its retries), so output can be shown before
  /// the run ends. A cancelled step has no result.
  /// [isCancelled] is polled before each step and again once a step's runner
  /// returns or throws; once true the in-flight step and every later one are
  /// reported `cancelled` and the run ends. It cannot stop a runner by itself —
  /// the caller interrupts that. [cancelSignal] completes at the same moment,
  /// so a wait between retries ends at once instead of out the full delay.
  ///
  /// A failing step ends the run unless its [RunbookStepModel.onFailure] is
  /// `continue`; either way the run's overall result is then a failure.
  Future<RunbookExecutionResult> executeRunbook(
    RunbookModel runbook,
    Future<(String output, int exitCode)> Function(
      String command,
      int timeoutSeconds,
    )
    commandRunner, {
    Map<String, String> variableValues = const {},
    void Function(RunbookStepModel step, String status)? onProgress,
    void Function(RunbookStepResult result)? onStepFinished,
    bool Function()? isCancelled,
    Future<void>? cancelSignal,
  }) async {
    final results = <RunbookStepResult>[];
    RunbookStepModel? firstFailure;

    // Sort steps by stepOrder
    final sortedSteps = List<RunbookStepModel>.from(runbook.steps)
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));

    bool cancelled() => isCancelled?.call() ?? false;

    RunbookExecutionResult cancelledFrom(int index) {
      for (final rest in sortedSteps.skip(index)) {
        onProgress?.call(rest, 'cancelled');
      }
      return RunbookExecutionResult(
        runbookId: runbook.id,
        overallSuccess: false,
        stepResults: results,
        failedStep: firstFailure,
        cancelled: true,
      );
    }

    for (var i = 0; i < sortedSteps.length; i++) {
      final step = sortedSteps[i];
      if (cancelled()) return cancelledFrom(i);
      onProgress?.call(step, 'running');

      // Substitute variables in command
      final commandToRun = SnippetVariableParser.substituteVariables(
        step.command,
        variableValues,
      );

      final stopwatch = Stopwatch()..start();
      final attempts = <StepAttempt>[];
      final maxAttempts =
          1 + step.retries.clamp(0, RunbookStepModel.maxRetries);
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        final outcome = await _attempt(step, commandToRun, commandRunner);
        if (cancelled()) return cancelledFrom(i);
        attempts.add(outcome);
        if (outcome.success || attempt == maxAttempts) break;
        await Future.any<void>([
          Future<void>.delayed(retryDelay),
          ?cancelSignal,
        ]);
        if (cancelled()) return cancelledFrom(i);
      }

      final last = attempts.last;
      final result = RunbookStepResult(
        step: step,
        success: last.success,
        exitCode: last.exitCode,
        output: last.output,
        errorMessage: last.errorMessage,
        command: commandToRun,
        attempts: attempts.length,
        attemptLog: attempts,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      results.add(result);
      onStepFinished?.call(result);

      if (last.success) {
        onProgress?.call(step, 'success');
        continue;
      }
      onProgress?.call(step, 'failed');
      firstFailure ??= step;
      if (step.onFailure == StepFailurePolicy.stop) {
        return RunbookExecutionResult(
          runbookId: runbook.id,
          overallSuccess: false,
          stepResults: results,
          failedStep: firstFailure,
        );
      }
    }

    return RunbookExecutionResult(
      runbookId: runbook.id,
      overallSuccess: firstFailure == null,
      stepResults: results,
      failedStep: firstFailure,
    );
  }

  /// Runs the step's command once and judges it against its expectations.
  Future<StepAttempt> _attempt(
    RunbookStepModel step,
    String command,
    Future<(String output, int exitCode)> Function(
      String command,
      int timeoutSeconds,
    )
    commandRunner,
  ) async {
    try {
      final (output, exitCode) = await commandRunner(
        command,
        step.timeoutSeconds,
      );

      // Check output verification pattern if specified
      bool patternMatches = true;
      String? patternError;
      if (step.expectedOutputPattern != null &&
          step.expectedOutputPattern!.isNotEmpty) {
        try {
          patternMatches = RegExp(step.expectedOutputPattern!).hasMatch(output);
        } catch (e) {
          patternMatches = false;
          patternError =
              'Invalid regex pattern "${step.expectedOutputPattern}": $e';
        }
      }

      final exitCodeMatches = exitCode == step.expectedExitCode;
      final success = patternMatches && exitCodeMatches;
      return StepAttempt(
        success: success,
        exitCode: exitCode,
        output: output,
        errorMessage: success
            ? null
            : (patternError ??
                  (exitCodeMatches
                      ? 'Output verification failed for pattern: "${step.expectedOutputPattern}"'
                      : 'Exit code $exitCode does not match expected ${step.expectedExitCode}')),
      );
    } catch (e) {
      return StepAttempt(
        success: false,
        output: '',
        errorMessage: e.toString(),
      );
    }
  }
}
