import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../data/run_providers.dart';
import '../../domain/models/active_run.dart';
import '../../domain/models/run_strategy.dart';
import '../../domain/models/runbook_model.dart';
import '../../domain/services/runbook_run_service.dart';

part 'runbook_run_notifier.g.dart';

/// Holds the run the Automation library is showing, so progress and Stop
/// outlive the widget that started it.
///
/// Kept alive, unlike the session-scoped providers: leaving the screen must
/// not silently cancel a deploy, and a settled run (a dialog may still be
/// about to read it) would otherwise vanish the moment nothing watched it.
/// What it retains once settled is plain data — every SSH session is closed in
/// the run service's `finally`, and disposing mid-run (the app container going
/// away) cancels the run, which closes the ones still open.
///
/// A run is written to local history once, when it settles (cancelled runs
/// included). A run cut off by the app quitting is therefore not recorded.
@Riverpod(keepAlive: true)
class RunbookRunNotifier extends _$RunbookRunNotifier {
  RunHandle? _run;

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
    RunStrategy strategy = RunStrategy.defaultParallel,
  }) async {
    if (isRunning) return;
    state = ActiveRun(
      runbook: runbook,
      running: true,
      strategy: strategy,
      variableValues: variableValues,
      startedAt: DateTime.now(),
      hosts: [
        for (final host in hosts)
          HostRunState(hostId: host.id, label: host.label),
      ],
    );

    final run = ref
        .read(runbookRunServiceProvider)
        .start(
          runbook,
          hosts,
          variableValues: variableValues,
          strategy: strategy,
          onEvent: _apply,
        );
    _run = run;
    try {
      await run.result;
      if (!ref.mounted) return;
      state = state?.copyWith(running: false, finishedAt: DateTime.now());
      await _record();
    } finally {
      _run = null;
    }
  }

  /// Writes the settled run to history. Best effort: a history failure must
  /// never turn a finished run into an error.
  Future<void> _record() async {
    final settled = state;
    if (settled == null) return;
    try {
      await ref.read(runHistoryRepositoryProvider).save(settled);
      if (ref.mounted) ref.read(runHistoryRevisionProvider.notifier).bump();
    } catch (_) {}
  }

  /// The saved hosts among [ids], in that order. Ids with no host (deleted
  /// since a stored run, or a default target list) are dropped.
  ///
  /// Awaits the host list rather than reading it: nothing is watching
  /// `hostsProvider` once the target sheet has closed, so it may not be loaded.
  Future<List<HostModel>> hostsFor(List<String> ids) async {
    final byId = {
      for (final host in await ref.read(hostsProvider.future)) host.id: host,
    };
    return [for (final id in ids) ?byId[id]];
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
    // Events keep arriving while a disposed run unwinds its cancel.
    if (!ref.mounted) return;
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      hosts: [
        for (final h in current.hosts)
          if (h.hostId != event.hostId)
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
              StepFinishedEvent(:final result) => h.copyWith(
                results: {...h.results, result.step.id: result},
              ),
            },
      ],
    );
  }
}

/// Bumped each time a run is written to history, so history lists and
/// last-run badges reload.
@Riverpod(keepAlive: true)
class RunHistoryRevision extends _$RunHistoryRevision {
  @override
  int build() => 0;

  void bump() => state++;
}
