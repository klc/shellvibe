import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../hosts/domain/models/host_model.dart';
import '../../data/run_providers.dart';
import '../../domain/models/runbook_model.dart';
import '../../domain/services/runbook_executor.dart';
import '../../domain/services/runbook_run_service.dart';

part 'runbook_run_notifier.g.dart';

/// One host's live state within an [ActiveRun].
class HostRunState {
  final HostModel host;
  final RunHostStatus status;

  /// Connection failure message, when the host never connected.
  final String? error;
  final Map<String, RunStepStatus> steps;

  /// Per-step output and exit codes; null until the host has finished.
  final RunbookExecutionResult? execution;

  const HostRunState({
    required this.host,
    this.status = RunHostStatus.queued,
    this.error,
    this.steps = const {},
    this.execution,
  });

  bool get finished => switch (status) {
    RunHostStatus.succeeded ||
    RunHostStatus.failed ||
    RunHostStatus.cancelled => true,
    _ => false,
  };

  HostRunState copyWith({
    RunHostStatus? status,
    String? error,
    Map<String, RunStepStatus>? steps,
    RunbookExecutionResult? execution,
  }) => HostRunState(
    host: host,
    status: status ?? this.status,
    error: error ?? this.error,
    steps: steps ?? this.steps,
    execution: execution ?? this.execution,
  );
}

/// The run on screen: a runbook (or a snippet wrapped as one) across its hosts.
class ActiveRun {
  final RunbookModel runbook;

  /// True while any host may still change; false once the run has settled.
  final bool running;

  /// [RunbookRun.cancel] was requested and the run is winding down.
  final bool cancelling;
  final List<HostRunState> hosts;

  const ActiveRun({
    required this.runbook,
    required this.running,
    this.cancelling = false,
    required this.hosts,
  });

  int get succeededCount =>
      hosts.where((h) => h.status == RunHostStatus.succeeded).length;

  ActiveRun copyWith({
    bool? running,
    bool? cancelling,
    List<HostRunState>? hosts,
  }) => ActiveRun(
    runbook: runbook,
    running: running ?? this.running,
    cancelling: cancelling ?? this.cancelling,
    hosts: hosts ?? this.hosts,
  );
}

/// Holds the run the Automation library is showing, so progress and Stop
/// outlive the widget that started it.
///
/// Auto-dispose, but kept alive while a run is in flight: leaving the screen
/// must not silently cancel a deploy, and a settled run has nothing left to
/// protect. Disposing mid-run (the app container going away) cancels it, which
/// closes every SSH session it opened.
@riverpod
class RunbookRunNotifier extends _$RunbookRunNotifier {
  RunbookRun? _run;
  KeepAliveLink? _keepAlive;

  @override
  ActiveRun? build() {
    ref.onDispose(() {
      final run = _run;
      _run = null;
      if (run != null) run.cancel();
    });
    return null;
  }

  /// True while a run is in flight; only one runs at a time.
  bool get isRunning => state?.running ?? false;

  /// Runs [runbook] on [hosts] and completes when every host has settled.
  Future<void> start(
    RunbookModel runbook,
    List<HostModel> hosts, {
    Map<String, String> variableValues = const {},
  }) async {
    if (isRunning) return;
    _keepAlive = ref.keepAlive();
    state = ActiveRun(
      runbook: runbook,
      running: true,
      hosts: [for (final host in hosts) HostRunState(host: host)],
    );

    final run = ref
        .read(runbookRunServiceProvider)
        .start(runbook, hosts, variableValues: variableValues, onEvent: _apply);
    _run = run;
    try {
      final results = await run.result;
      if (!ref.mounted) return;
      final byHost = {for (final r in results) r.host.id: r};
      state = state?.copyWith(
        running: false,
        hosts: [
          for (final h in state!.hosts)
            if (byHost[h.host.id] case final r?)
              h.copyWith(execution: r.execution)
            else
              h,
        ],
      );
    } finally {
      _run = null;
      _keepAlive?.close();
      _keepAlive = null;
    }
  }

  /// Asks the in-flight run to stop. A no-op when nothing is running.
  Future<void> cancel() async {
    final run = _run;
    if (run == null || state == null) return;
    state = state!.copyWith(cancelling: true);
    await run.cancel();
  }

  /// Forgets a settled run, e.g. when its results panel is dismissed.
  void clear() {
    if (isRunning) return;
    state = null;
  }

  void _apply(RunEvent event) {
    final current = state;
    if (current == null || !ref.mounted) return;
    state = current.copyWith(
      hosts: [
        for (final h in current.hosts)
          if (h.host.id != event.hostId)
            h
          else
            switch (event) {
              HostStatusEvent(:final status, :final error) => h.copyWith(
                status: status,
                error: error,
              ),
              StepStatusEvent(:final stepId, :final status) => h.copyWith(
                steps: {...h.steps, stepId: status},
              ),
            },
      ],
    );
  }
}
