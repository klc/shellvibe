import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../hosts/domain/models/host_model.dart';
import '../../snippets/domain/models/active_run.dart';
import '../../snippets/domain/models/run_strategy.dart';
import '../../snippets/domain/models/runbook_model.dart';
import '../../snippets/presentation/notifiers/runbook_run_notifier.dart';
import 'tools/runbook_tools.dart';

/// The runbook tools' view of the app's one run: the same `RunbookRunNotifier`
/// the library screens use, so a run an agent starts shows in the run view,
/// stops at approval steps, can be stopped from the UI and lands in history
/// exactly like one the user started.
class NotifierRunbookRunGateway implements RunbookRunGateway {
  final Ref _ref;

  const NotifierRunbookRunGateway(this._ref);

  RunbookRunNotifier get _notifier => _ref.read(runbookRunProvider.notifier);

  @override
  ActiveRun? get current => _ref.read(runbookRunProvider);

  @override
  bool get isRunning => _notifier.isRunning;

  @override
  Future<void> start(
    RunbookModel runbook,
    List<HostModel> hosts, {
    required Map<String, String> variableValues,
    required RunStrategy strategy,
    required RunTrigger triggeredBy,
    required String runId,
  }) {
    return _notifier.start(
      runbook,
      hosts,
      variableValues: variableValues,
      strategy: strategy,
      triggeredBy: triggeredBy,
      runId: runId,
    );
  }

  @override
  Future<void> cancel() => _notifier.cancel();
}
