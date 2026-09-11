import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'runbooks_dao.g.dart';

@DriftAccessor(tables: [Runbooks, RunbookSteps])
class RunbooksDao extends DatabaseAccessor<AppDatabase>
    with _$RunbooksDaoMixin {
  RunbooksDao(super.db);

  Future<List<Runbook>> getAllRunbooks() => select(runbooks).get();

  Future<List<Runbook>> getRunbooksByWorkspace(String workspaceId) {
    return (select(
      runbooks,
    )..where((tbl) => tbl.workspaceId.equals(workspaceId))).get();
  }

  Stream<List<Runbook>> watchAllRunbooks() => select(runbooks).watch();

  Future<List<RunbookStep>> getStepsForRunbook(String runbookId) {
    return (select(runbookSteps)
          ..where((tbl) => tbl.runbookId.equals(runbookId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.stepOrder)]))
        .get();
  }

  Future<int> insertRunbook(RunbooksCompanion runbook) =>
      into(runbooks).insert(runbook);

  Future<bool> updateRunbook(RunbooksCompanion runbook) =>
      update(runbooks).replace(runbook);

  Future<int> deleteRunbook(String id) async {
    await (delete(runbookSteps)..where((tbl) => tbl.runbookId.equals(id))).go();
    return (delete(runbooks)..where((tbl) => tbl.id.equals(id))).go();
  }

  Future<void> replaceSteps(
    String runbookId,
    List<RunbookStepsCompanion> steps,
  ) async {
    await transaction(() async {
      await (delete(
        runbookSteps,
      )..where((tbl) => tbl.runbookId.equals(runbookId))).go();
      for (final step in steps) {
        await into(runbookSteps).insert(step);
      }
    });
  }
}
