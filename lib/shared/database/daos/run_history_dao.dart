import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'run_history_dao.g.dart';

/// Local run history. Plain writes on purpose: none of these tables are synced,
/// so nothing here goes through `recordUpsert` / `recordDelete`.
@DriftAccessor(tables: [RunbookRuns, RunbookRunHosts, RunbookRunSteps])
class RunHistoryDao extends DatabaseAccessor<AppDatabase>
    with _$RunHistoryDaoMixin {
  RunHistoryDao(super.db);

  /// Retention: runs kept per runbook, and snippet runs kept overall.
  static const int runbookRetention = 20;
  static const int snippetRetention = 50;

  /// Stores one settled run with its hosts and steps, then prunes what the
  /// retention limits no longer keep, in one transaction.
  Future<void> insertRun(
    RunbookRunsCompanion run,
    List<RunbookRunHostsCompanion> hosts,
    List<RunbookRunStepsCompanion> steps,
  ) {
    return transaction(() async {
      await into(runbookRuns).insert(run);
      await batch((b) {
        b.insertAll(runbookRunHosts, hosts);
        b.insertAll(runbookRunSteps, steps);
      });
      await _prune(run);
    });
  }

  Future<void> _prune(RunbookRunsCompanion run) async {
    final runbookId = run.runbookId.value;
    final isSnippet = run.kind.value == 'snippet';
    final scope = select(runbookRuns)
      ..where(
        (t) => isSnippet
            ? t.kind.equals('snippet')
            : t.runbookId.equals(runbookId!),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
    final all = await scope.get();
    final keep = isSnippet ? snippetRetention : runbookRetention;
    if (all.length <= keep) return;
    final doomed = all.skip(keep).map((r) => r.id).toList();
    await (delete(runbookRuns)..where((t) => t.id.isIn(doomed))).go();
  }

  Future<List<RunbookRun>> runsForRunbook(String runbookId, {int? limit}) {
    final q = select(runbookRuns)
      ..where((t) => t.runbookId.equals(runbookId))
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
    if (limit != null) q.limit(limit);
    return q.get();
  }

  Future<List<RunbookRun>> snippetRuns({int? limit}) {
    final q = select(runbookRuns)
      ..where((t) => t.kind.equals('snippet'))
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
    if (limit != null) q.limit(limit);
    return q.get();
  }

  Future<RunbookRun?> getRun(String id) =>
      (select(runbookRuns)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<RunbookRunHost>> hostsForRun(String runId) =>
      (select(runbookRunHosts)
            ..where((t) => t.runId.equals(runId))
            ..orderBy([(t) => OrderingTerm.asc(t.position)]))
          .get();

  Future<List<RunbookRunStep>> stepsForRun(String runId) {
    final q = select(runbookRunSteps).join([
      innerJoin(
        runbookRunHosts,
        runbookRunHosts.id.equalsExp(runbookRunSteps.runHostId),
      ),
    ])..where(runbookRunHosts.runId.equals(runId));
    return q.map((row) => row.readTable(runbookRunSteps)).get();
  }

  /// Deletes a runbook's history, or every snippet run when [runbookId] is
  /// null.
  Future<void> clear({String? runbookId}) async {
    await (delete(runbookRuns)..where(
          (t) => runbookId == null
              ? t.kind.equals('snippet')
              : t.runbookId.equals(runbookId),
        ))
        .go();
  }
}
