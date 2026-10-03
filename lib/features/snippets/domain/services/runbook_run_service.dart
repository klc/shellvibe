import 'dart:async';

import '../../../hosts/domain/models/host_model.dart';
import '../models/runbook_model.dart';
import '../models/runbook_step_model.dart';
import '../models/snippet_model.dart';
import 'remote_command_session.dart';
import 'runbook_executor.dart';

/// Lifecycle of one step on one host.
enum RunStepStatus { pending, running, success, failed, cancelled }

/// Lifecycle of one host within a run.
enum RunHostStatus {
  /// Waiting for a concurrency slot.
  queued,
  connecting,

  /// Connected; steps are executing.
  running,
  succeeded,

  /// Either the connection failed (no step ran) or a step failed.
  failed,
  cancelled,
}

/// A progress notification from a [RunbookRun].
sealed class RunEvent {
  final String hostId;
  const RunEvent(this.hostId);
}

/// A host moved to [status]; [error] carries the connection failure message.
class HostStatusEvent extends RunEvent {
  final RunHostStatus status;
  final String? error;
  const HostStatusEvent(super.hostId, this.status, {this.error});
}

/// A step on [hostId] moved to [status].
class StepStatusEvent extends RunEvent {
  final String stepId;
  final RunStepStatus status;
  const StepStatusEvent(super.hostId, this.stepId, this.status);
}

/// How one host ended.
class HostRunResult {
  final HostModel host;
  final RunHostStatus status;

  /// Set when the connection could not be established; no step ran then.
  final String? connectionError;

  /// Null when the host never got as far as running steps.
  final RunbookExecutionResult? execution;

  const HostRunResult({
    required this.host,
    required this.status,
    this.connectionError,
    this.execution,
  });
}

/// A run in flight: await [result], or [cancel] it.
class RunbookRun {
  final Future<List<HostRunResult>> result;
  final Future<void> Function() _cancel;

  RunbookRun(this.result, this._cancel);

  /// Interrupts and closes every open session and marks unfinished steps
  /// cancelled. [result] still completes (with cancelled hosts); it never
  /// hangs on a connection attempt or a command that will not return.
  Future<void> cancel() => _cancel();
}

/// Runs one runbook against many hosts.
///
/// Each host gets its own session, opened, driven through the existing
/// [RunbookExecutor] and closed in `finally`. Hosts are independent: one that
/// cannot connect or fails a step never stops the others, while inside a host
/// the executor's stop-at-first-failure rule still holds, because running
/// step 3 after step 2 failed is how a deploy half-applies.
class RunbookRunService {
  /// Hosts running at once. Fixed: every host is a fresh SSH connection (plus
  /// its jump chain), and a runbook against fifty hosts should not open fifty.
  static const int maxConcurrentHosts = 4;

  final RemoteCommandSessionFactory sessionFactory;
  final RunbookExecutor _executor;

  RunbookRunService({required this.sessionFactory, RunbookExecutor? executor})
    : _executor = executor ?? RunbookExecutor();

  /// A snippet as the one-step runbook it is, so snippets and runbooks share
  /// one engine instead of two that disagree about exit codes.
  static RunbookModel runbookForSnippet(
    SnippetModel snippet, {
    int timeoutSeconds = 60,
  }) {
    final runbookId = 'snippet:${snippet.id}';
    return RunbookModel(
      id: runbookId,
      workspaceId: snippet.workspaceId,
      title: snippet.title,
      createdAt: DateTime.now(),
      steps: [
        RunbookStepModel(
          id: '$runbookId:1',
          runbookId: runbookId,
          stepOrder: 1,
          command: snippet.code,
          timeoutSeconds: timeoutSeconds,
        ),
      ],
    );
  }

  /// Starts [runbook] on every host in [hosts] and reports through [onEvent].
  ///
  /// Every host and step is announced `queued` / `pending` up front so a UI
  /// can lay the whole grid out before anything has connected.
  RunbookRun start(
    RunbookModel runbook,
    List<HostModel> hosts, {
    Map<String, String> variableValues = const {},
    void Function(RunEvent event)? onEvent,
  }) {
    final steps = List<RunbookStepModel>.from(runbook.steps)
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
    final cancelSignal = Completer<void>();
    final openSessions = <RemoteCommandSession>{};
    var cancelled = false;

    void emit(RunEvent event) => onEvent?.call(event);

    for (final host in hosts) {
      emit(HostStatusEvent(host.id, RunHostStatus.queued));
      for (final step in steps) {
        emit(StepStatusEvent(host.id, step.id, RunStepStatus.pending));
      }
    }

    void cancelRemaining(HostModel host, Iterable<RunbookStepModel> rest) {
      emit(HostStatusEvent(host.id, RunHostStatus.cancelled));
      for (final step in rest) {
        emit(StepStatusEvent(host.id, step.id, RunStepStatus.cancelled));
      }
    }

    Future<HostRunResult> runHost(HostModel host) async {
      if (cancelled) {
        cancelRemaining(host, steps);
        return HostRunResult(host: host, status: RunHostStatus.cancelled);
      }
      emit(HostStatusEvent(host.id, RunHostStatus.connecting));

      RemoteCommandSession? session;
      try {
        final opening = sessionFactory.open(host);
        final opened = await Future.any<RemoteCommandSession?>([
          opening,
          cancelSignal.future.then((_) => null),
        ]);
        if (opened == null) {
          // Cancelled mid-connect: the attempt cannot be aborted, so whatever
          // it eventually yields is closed instead of leaked.
          unawaited(
            opening.then<void>((late) => late.close(), onError: (Object _) {}),
          );
          cancelRemaining(host, steps);
          return HostRunResult(host: host, status: RunHostStatus.cancelled);
        }
        session = opened;
        openSessions.add(session);
      } catch (e) {
        final message = _describe(e);
        emit(HostStatusEvent(host.id, RunHostStatus.failed, error: message));
        return HostRunResult(
          host: host,
          status: RunHostStatus.failed,
          connectionError: message,
        );
      }

      try {
        emit(HostStatusEvent(host.id, RunHostStatus.running));
        final execution = await _executor.executeRunbook(
          runbook,
          (command, timeoutSeconds) async {
            // Raced against cancel so a command that ignores the interrupt
            // cannot keep the run alive.
            final result = await Future.any<(String, int)?>([
              session!.run(command, Duration(seconds: timeoutSeconds)),
              cancelSignal.future.then((_) => null),
            ]);
            if (result == null) throw const _RunCancelled();
            return result;
          },
          variableValues: variableValues,
          isCancelled: () => cancelled,
          onProgress: (step, status) {
            final mapped = switch (status) {
              'running' => RunStepStatus.running,
              'success' => RunStepStatus.success,
              'cancelled' => RunStepStatus.cancelled,
              _ => RunStepStatus.failed,
            };
            emit(StepStatusEvent(host.id, step.id, mapped));
          },
        );
        final status = execution.cancelled
            ? RunHostStatus.cancelled
            : execution.overallSuccess
            ? RunHostStatus.succeeded
            : RunHostStatus.failed;
        emit(HostStatusEvent(host.id, status));
        return HostRunResult(host: host, status: status, execution: execution);
      } finally {
        openSessions.remove(session);
        try {
          await session.close();
        } catch (_) {}
      }
    }

    Future<List<HostRunResult>> runAll() async {
      final results = List<HostRunResult?>.filled(hosts.length, null);
      var next = 0;
      Future<void> worker() async {
        while (next < hosts.length) {
          final index = next++;
          results[index] = await runHost(hosts[index]);
        }
      }

      final workerCount = hosts.length < maxConcurrentHosts
          ? hosts.length
          : maxConcurrentHosts;
      await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
      return results.whereType<HostRunResult>().toList();
    }

    Future<void> cancel() async {
      if (cancelled) return;
      cancelled = true;
      if (!cancelSignal.isCompleted) cancelSignal.complete();
      // Interrupt, then close: the interrupt is what stops a running command
      // on the server; closing alone would leave it running detached.
      for (final session in openSessions.toList()) {
        try {
          await session.interrupt();
        } catch (_) {}
        try {
          await session.close();
        } catch (_) {}
      }
    }

    return RunbookRun(runAll(), cancel);
  }

  static String _describe(Object error) => switch (error) {
    RemoteCommandException(:final message) => message,
    TimeoutException(:final message?) => message,
    _ => error.toString(),
  };
}

/// Thrown into the executor when a cancel wins the race against a command, so
/// it unwinds as a cancelled step rather than a failed one.
class _RunCancelled implements Exception {
  const _RunCancelled();
}
