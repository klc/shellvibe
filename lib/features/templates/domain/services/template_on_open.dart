import '../../../hosts/domain/models/host_model.dart';
import '../../../snippets/domain/models/runbook_model.dart';
import '../../../snippets/domain/models/snippet_model.dart';
import '../../../snippets/domain/services/run_variables.dart';
import '../models/template_model.dart';
import 'template_hosts.dart';

/// What came of a template's on-open runbook.
enum OnOpenOutcome {
  /// The template has none.
  notConfigured,

  /// It names a runbook that no longer exists.
  runbookMissing,

  /// None of the template's panes is on an SSH host to run it on.
  noHosts,

  /// Another run is in progress; only one runs at a time.
  busy,

  /// The user declined the confirmation.
  declined,

  /// The user backed out of the variables prompt.
  inputCancelled,
  started,
}

/// Starts a template's on-open runbook once the layout has been replayed.
///
/// Pure Dart: every question and effect crosses a callback, so the rules —
/// when to ask, when to prompt, when to stay out of the way — are tested
/// without a widget tree. The UI wires the callbacks to dialogs and the run
/// notifier.
class TemplateOnOpen {
  /// Whether a run is already in progress.
  final bool Function() isRunning;

  /// Asks the user to confirm running [runbook] on [hosts].
  final Future<bool> Function(RunbookModel runbook, List<HostModel> hosts)
  confirm;

  /// Asks for `${INPUT:...}` values; null when the user cancels. Never called
  /// with an empty list.
  final Future<Map<String, String>?> Function(
    RunbookModel runbook,
    RunVariables variables,
  )
  promptVariables;

  /// Starts the run in the background on [hosts], with the default strategy.
  final void Function(
    RunbookModel runbook,
    List<HostModel> hosts,
    Map<String, String> variableValues,
  )
  start;

  /// Tells the user something. [offerRunView] attaches an action that opens
  /// the run view.
  final void Function(String message, {bool offerRunView}) notify;

  const TemplateOnOpen({
    required this.isRunning,
    required this.confirm,
    required this.promptVariables,
    required this.start,
    required this.notify,
  });

  Future<OnOpenOutcome> run(
    TemplateModel template, {
    required List<RunbookModel> runbooks,
    required Map<String, HostModel> hostsById,
    Map<String, SnippetModel> snippets = const {},
  }) async {
    final runbookId = template.onOpenRunbookId;
    if (runbookId == null) return OnOpenOutcome.notConfigured;
    final runbook = runbooks.where((r) => r.id == runbookId).firstOrNull;
    if (runbook == null) return OnOpenOutcome.runbookMissing;

    final hosts = resolveTemplateHosts(template, hostsById).hosts;
    if (hosts.isEmpty) {
      notify(
        'Runbook "${runbook.title}" was not run: "${template.name}" has no '
        'SSH host to run it on.',
      );
      return OnOpenOutcome.noHosts;
    }
    if (isRunning()) {
      notify(
        'Runbook "${runbook.title}" was not run: another run is in progress.',
      );
      return OnOpenOutcome.busy;
    }

    // Production always asks, whatever "ask before running" says: a layout
    // being opened must not start a runbook on a prod host unattended.
    final mustAsk = template.onOpenConfirm || hosts.any((h) => h.isProd);
    if (mustAsk && !await confirm(runbook, hosts)) {
      return OnOpenOutcome.declined;
    }

    // Never started with blanks: a runbook that wants input is asked, whatever
    // "ask before running" says.
    final variables = collectRunVariables(runbook, snippets: snippets);
    var values = <String, String>{};
    if (!variables.isEmpty) {
      final entered = await promptVariables(runbook, variables);
      if (entered == null) return OnOpenOutcome.inputCancelled;
      values = entered;
    }

    // The prompts above are awaited, so the answer to "is something running"
    // is read again before committing.
    if (isRunning()) {
      notify(
        'Runbook "${runbook.title}" was not run: another run is in progress.',
      );
      return OnOpenOutcome.busy;
    }
    start(runbook, hosts, values);
    notify(
      'Running "${runbook.title}" on ${hosts.length} '
      '${hosts.length == 1 ? 'host' : 'hosts'}.',
      offerRunView: true,
    );
    return OnOpenOutcome.started;
  }
}
