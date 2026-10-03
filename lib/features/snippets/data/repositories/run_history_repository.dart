import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/run_history_dao.dart';
import '../../domain/models/active_run.dart';
import '../../domain/models/run_strategy.dart';
import '../../domain/models/runbook_model.dart';
import '../../domain/models/runbook_step_model.dart';
import '../../domain/services/runbook_executor.dart';
import '../../domain/services/runbook_run_service.dart';

/// One line of a history list.
class RunHistorySummary {
  final String id;
  final String? runbookId;

  /// Set for a snippet run: which snippet it was of.
  final String? snippetId;
  final String kind;
  final String title;
  final RunStrategy strategy;
  final DateTime startedAt;
  final DateTime finishedAt;

  /// `succeeded`, `failed` or `cancelled`.
  final String status;
  final int hostCount;
  final int succeededHosts;

  const RunHistorySummary({
    required this.id,
    required this.runbookId,
    required this.snippetId,
    required this.kind,
    required this.title,
    required this.strategy,
    required this.startedAt,
    required this.finishedAt,
    required this.status,
    required this.hostCount,
    required this.succeededHosts,
  });

  String get summaryText =>
      '$succeededHosts of $hostCount ${hostCount == 1 ? 'host' : 'hosts'} '
      'succeeded';
}

/// A stored run read back into the shape the live view renders.
class StoredRun {
  final RunHistorySummary summary;
  final ActiveRun run;

  /// Hosts in the order they were run, to be re-resolved against the live
  /// host list: some may be gone.
  final List<String> hostIds;

  const StoredRun({
    required this.summary,
    required this.run,
    required this.hostIds,
  });
}

/// Local run history.
///
/// Stored as snapshots (labels, substituted commands) so a run still renders
/// after its runbook or hosts are edited or deleted. A run that was still in
/// flight when the app quit is never written: persistence happens once, when a
/// run settles, so there is nothing half-recorded to clean up.
///
/// Never synced or backed up. Output is stored here and can contain secrets;
/// the database file is not encrypted, so only the last [maxOutputBytes] of
/// each step is kept.
class RunHistoryRepository {
  final RunHistoryDao _dao;
  final _uuid = const Uuid();

  RunHistoryRepository(this._dao);

  static const int maxOutputBytes = 16 * 1024;

  /// Stores a settled [run]. Prunes to the retention limits as it inserts.
  Future<String> save(ActiveRun run) async {
    final runId = _uuid.v4();
    final isSnippet = RunbookRunService.isSnippetRunbook(run.runbook);
    final steps = List<RunbookStepModel>.from(run.runbook.steps)
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));

    final hostRows = <RunbookRunHostsCompanion>[];
    final stepRows = <RunbookRunStepsCompanion>[];
    for (var i = 0; i < run.hosts.length; i++) {
      final host = run.hosts[i];
      final hostRowId = _uuid.v4();
      hostRows.add(
        RunbookRunHostsCompanion.insert(
          id: hostRowId,
          runId: runId,
          position: i,
          hostId: host.hostId,
          hostLabel: host.label,
          status: host.status.name,
          error: Value(host.error),
        ),
      );
      for (final step in steps) {
        final result = host.results[step.id];
        final (output, truncated) = _tail(
          _redact(result?.output ?? '', run.variableValues),
        );
        stepRows.add(
          RunbookRunStepsCompanion.insert(
            id: _uuid.v4(),
            runHostId: hostRowId,
            stepId: step.id,
            stepOrder: step.stepOrder,
            kind: Value(step.kind.name),
            // The template, never the substituted command: an `${INPUT:...}`
            // value is exactly what must not reach this unencrypted file.
            command: step.command,
            status: (host.steps[step.id] ?? RunStepStatus.pending).name,
            exitCode: Value(result?.exitCode),
            attempts: Value(result?.attempts ?? 0),
            output: Value(output),
            outputTruncated: Value(
              truncated || (result?.outputTruncated ?? false),
            ),
            error: Value(
              result?.errorMessage == null
                  ? null
                  : _redact(result!.errorMessage!, run.variableValues),
            ),
            durationMs: Value(result?.durationMs),
          ),
        );
      }
    }

    await _dao.insertRun(
      RunbookRunsCompanion.insert(
        id: runId,
        workspaceId: run.runbook.workspaceId,
        runbookId: Value(isSnippet ? null : run.runbook.id),
        snippetId: Value(
          isSnippet
              ? run.runbook.id.substring(
                  RunbookRunService.snippetRunbookPrefix.length,
                )
              : null,
        ),
        kind: isSnippet ? 'snippet' : 'runbook',
        title: run.runbook.title,
        strategy: run.strategy.wireName,
        startedAt: run.startedAt,
        finishedAt: run.finishedAt ?? DateTime.now(),
        status: run.outcome,
        variableValues: Value(
          jsonEncode(run.variableValues.keys.toList()..sort()),
        ),
      ),
      hostRows,
      stepRows,
    );
    return runId;
  }

  /// Output with every non-empty input value masked. Exact matches only: a
  /// program that transforms the value before echoing it is out of reach, which
  /// is why the values are also never stored themselves.
  static String _redact(String text, Map<String, String> values) {
    var result = text;
    final secrets = values.values.where((v) => v.isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final secret in secrets) {
      result = result.replaceAll(secret, '[redacted]');
    }
    return result;
  }

  /// The last [maxOutputBytes] of [output], cut on a character boundary.
  static (String, bool) _tail(String output) {
    final bytes = utf8.encode(output);
    if (bytes.length <= maxOutputBytes) return (output, false);
    final cut = utf8.decode(
      bytes.sublist(bytes.length - maxOutputBytes),
      allowMalformed: true,
    );
    // A cut inside a multi-byte character leaves a replacement char at the
    // front; drop it rather than show it.
    return (cut.startsWith('�') ? cut.substring(1) : cut, true);
  }

  Future<List<RunHistorySummary>> forRunbook(String runbookId, {int? limit}) =>
      _summaries(_dao.runsForRunbook(runbookId, limit: limit));

  Future<List<RunHistorySummary>> forSnippets({int? limit}) =>
      _summaries(_dao.snippetRuns(limit: limit));

  /// One snippet's runs, newest first.
  Future<List<RunHistorySummary>> forSnippet(String snippetId, {int? limit}) =>
      _summaries(_dao.runsForSnippet(snippetId, limit: limit));

  /// The most recent run of each runbook in [runbookIds], for list badges.
  Future<Map<String, RunHistorySummary>> latestByRunbook(
    Iterable<String> runbookIds,
  ) async {
    final latest = <String, RunHistorySummary>{};
    for (final id in runbookIds) {
      final runs = await forRunbook(id, limit: 1);
      if (runs.isNotEmpty) latest[id] = runs.first;
    }
    return latest;
  }

  Future<List<RunHistorySummary>> _summaries(
    Future<List<RunbookRun>> query,
  ) async {
    final result = <RunHistorySummary>[];
    for (final row in await query) {
      final hosts = await _dao.hostsForRun(row.id);
      result.add(_summary(row, hosts));
    }
    return result;
  }

  RunHistorySummary _summary(RunbookRun row, List<RunbookRunHost> hosts) =>
      RunHistorySummary(
        id: row.id,
        runbookId: row.runbookId,
        snippetId: row.snippetId,
        kind: row.kind,
        title: row.title,
        strategy: RunStrategy.parse(row.strategy),
        startedAt: row.startedAt,
        finishedAt: row.finishedAt,
        status: row.status,
        hostCount: hosts.length,
        succeededHosts: hosts
            .where((h) => h.status == RunHostStatus.succeeded.name)
            .length,
      );

  /// Reads one run back for display; null when it has been pruned.
  Future<StoredRun?> load(String runId) async {
    final row = await _dao.getRun(runId);
    if (row == null) return null;
    final hostRows = await _dao.hostsForRun(runId);
    final stepRows = await _dao.stepsForRun(runId);

    final stepsByHost = <String, List<RunbookRunStep>>{};
    for (final s in stepRows) {
      stepsByHost.putIfAbsent(s.runHostId, () => []).add(s);
    }

    // The runbook is rebuilt from what was stored, not looked up: it may have
    // been edited since.
    final firstHostSteps = hostRows.isEmpty
        ? const <RunbookRunStep>[]
        : (stepsByHost[hostRows.first.id] ?? const <RunbookRunStep>[]);
    final ordered = List<RunbookRunStep>.from(firstHostSteps)
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
    final runbook = RunbookModel(
      id: row.runbookId ?? 'history:${row.id}',
      workspaceId: row.workspaceId,
      title: row.title,
      createdAt: row.startedAt,
      steps: [
        for (final s in ordered)
          RunbookStepModel(
            id: s.stepId,
            runbookId: row.runbookId ?? 'history:${row.id}',
            stepOrder: s.stepOrder,
            command: s.command,
            kind: StepKind.parse(s.kind),
          ),
      ],
    );

    final hosts = <HostRunState>[];
    for (final h in hostRows) {
      final statuses = <String, RunStepStatus>{};
      final results = <String, RunbookStepResult>{};
      for (final s in stepsByHost[h.id] ?? const <RunbookRunStep>[]) {
        final status = RunStepStatus.values.byName(s.status);
        statuses[s.stepId] = status;
        if (s.attempts > 0) {
          results[s.stepId] = RunbookStepResult(
            step: runbook.steps.firstWhere((x) => x.id == s.stepId),
            success: status == RunStepStatus.success,
            exitCode: s.exitCode,
            output: s.output,
            errorMessage: s.error,
            command: s.command,
            attempts: s.attempts,
            durationMs: s.durationMs,
            outputTruncated: s.outputTruncated,
          );
        }
      }
      hosts.add(
        HostRunState(
          hostId: h.hostId,
          label: h.hostLabel,
          status: RunHostStatus.values.byName(h.status),
          error: h.error,
          steps: statuses,
          results: results,
        ),
      );
    }

    return StoredRun(
      summary: _summary(row, hostRows),
      hostIds: [for (final h in hostRows) h.hostId],
      run: ActiveRun(
        runbook: runbook,
        running: false,
        hosts: hosts,
        strategy: RunStrategy.parse(row.strategy),
        // Never stored, so a re-run from history asks again.
        startedAt: row.startedAt,
        finishedAt: row.finishedAt,
        fromHistory: true,
      ),
    );
  }

  /// Deletes a runbook's history, a snippet's, or every snippet run when
  /// neither is given.
  Future<void> clear({String? runbookId, String? snippetId}) =>
      _dao.clear(runbookId: runbookId, snippetId: snippetId);
}
