import '../services/runbook_executor.dart';
import '../services/runbook_run_service.dart';
import 'run_strategy.dart';
import 'runbook_model.dart';

/// One host's state within a run: live, or read back from history.
///
/// Carries the label rather than the `HostModel` so a stored run still renders
/// after its host was renamed or deleted.
class HostRunState {
  final String hostId;
  final String label;
  final RunHostStatus status;

  /// Connection failure message, when the host never connected.
  final String? error;
  final Map<String, RunStepStatus> steps;

  /// Each step's result as soon as it settles, so its output can be opened
  /// while later steps (and other hosts) are still running.
  final Map<String, RunbookStepResult> results;

  const HostRunState({
    required this.hostId,
    required this.label,
    this.status = RunHostStatus.queued,
    this.error,
    this.steps = const {},
    this.results = const {},
  });

  bool get finished => switch (status) {
    RunHostStatus.succeeded ||
    RunHostStatus.failed ||
    RunHostStatus.cancelled ||
    RunHostStatus.skipped => true,
    _ => false,
  };

  HostRunState copyWith({
    RunHostStatus? status,
    String? error,
    Map<String, RunStepStatus>? steps,
    Map<String, RunbookStepResult>? results,
  }) => HostRunState(
    hostId: hostId,
    label: label,
    status: status ?? this.status,
    error: error ?? this.error,
    steps: steps ?? this.steps,
    results: results ?? this.results,
  );
}

/// A run on screen: a runbook (or a snippet wrapped as one) across its hosts.
/// Also the shape a stored run is read back into, so the live view and the
/// history view are one widget over one model.
class ActiveRun {
  final RunbookModel runbook;

  /// True while any host may still change; false once the run has settled.
  final bool running;

  /// [RunHandle.cancel] was requested and the run is winding down.
  final bool cancelling;
  final List<HostRunState> hosts;
  final RunStrategy strategy;

  /// The `${INPUT:...}` values the run used, kept so a re-run repeats it.
  final Map<String, String> variableValues;
  final DateTime startedAt;
  final DateTime? finishedAt;

  /// Set for a run read back from history; there is nothing to stop or retry.
  final bool fromHistory;

  const ActiveRun({
    required this.runbook,
    required this.running,
    this.cancelling = false,
    required this.hosts,
    this.strategy = RunStrategy.defaultParallel,
    this.variableValues = const {},
    required this.startedAt,
    this.finishedAt,
    this.fromHistory = false,
  });

  int _count(RunHostStatus status) =>
      hosts.where((h) => h.status == status).length;

  int get succeededCount => _count(RunHostStatus.succeeded);
  int get failedCount => _count(RunHostStatus.failed);
  int get skippedCount => _count(RunHostStatus.skipped);
  int get cancelledCount => _count(RunHostStatus.cancelled);

  /// The host a rolling run stopped after, or null when it did not stop early.
  String? get stoppedAfter {
    if (!strategy.isRolling || skippedCount == 0) return null;
    return hosts
        .where((h) => h.status == RunHostStatus.failed)
        .firstOrNull
        ?.label;
  }

  /// Wall time so far, or the total once settled.
  Duration elapsed(DateTime now) => (finishedAt ?? now).difference(startedAt);

  /// `succeeded`, `failed` or `cancelled`: how a settled run is filed.
  String get outcome {
    if (cancelledCount > 0) return 'cancelled';
    if (failedCount > 0) return 'failed';
    return 'succeeded';
  }

  ActiveRun copyWith({
    bool? running,
    bool? cancelling,
    List<HostRunState>? hosts,
    DateTime? finishedAt,
  }) => ActiveRun(
    runbook: runbook,
    running: running ?? this.running,
    cancelling: cancelling ?? this.cancelling,
    hosts: hosts ?? this.hosts,
    strategy: strategy,
    variableValues: variableValues,
    startedAt: startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    fromHistory: fromHistory,
  );
}
