import '../../../hosts/domain/models/host_model.dart';
import 'run_strategy.dart';

/// Where a snippet or runbook is about to run.
sealed class RunTarget {
  const RunTarget();
}

/// A background, verified run on a saved host: a dedicated connection whose
/// exit codes are real.
class HostRunTarget extends RunTarget {
  final HostModel host;
  const HostRunTarget(this.host);
}

/// Types the command into the focused terminal pane. Unverified: the app
/// cannot see what the shell did with it. Snippets only.
class ActivePaneRunTarget extends RunTarget {
  const ActivePaneRunTarget();
}

/// Types the command into every pane of the current broadcast selection.
/// Unverified, snippets only.
class SelectedPanesRunTarget extends RunTarget {
  const SelectedPanesRunTarget();
}

/// What the target sheet resolves to.
class RunTargetSelection {
  /// One [HostRunTarget] per host, or a single terminal target.
  final List<RunTarget> targets;
  final RunStrategy strategy;

  /// The user asked to remember the chosen hosts as the runbook's default.
  final bool saveAsDefault;

  const RunTargetSelection(
    this.targets, {
    this.strategy = RunStrategy.defaultParallel,
    this.saveAsDefault = false,
  });

  List<HostModel> get hosts => [
    for (final target in targets)
      if (target is HostRunTarget) target.host,
  ];
}
