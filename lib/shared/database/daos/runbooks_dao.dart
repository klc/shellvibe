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

  Future<int> insertRunbook(RunbooksCompanion runbook) => db.recordUpsert(
    entityType: 'runbooks',
    entityId: runbook.id.value,
    write: () => into(runbooks).insert(runbook),
  );

  Future<bool> updateRunbook(RunbooksCompanion runbook) => db.recordUpsert(
    entityType: 'runbooks',
    entityId: runbook.id.value,
    write: () => update(runbooks).replace(runbook),
  );

  /// Deletes the runbook. Its steps go with it.
  ///
  /// The explicit step delete is gone: `runbook_steps.runbook_id` cascades, so
  /// the database was going to remove them anyway, and doing it by hand meant
  /// the sync journal saw a bare delete it could not attribute. It records the
  /// cascade itself.
  Future<int> deleteRunbook(String id) => db.recordDelete(
    entityType: 'runbooks',
    entityId: id,
    write: () => (delete(runbooks)..where((tbl) => tbl.id.equals(id))).go(),
  );

  Future<void> replaceSteps(
    String runbookId,
    List<RunbookStepsCompanion> steps,
  ) async {
    await transaction(() async {
      final removed = await (select(
        runbookSteps,
      )..where((tbl) => tbl.runbookId.equals(runbookId))).get();

      for (final step in removed) {
        await db.recordDelete(
          entityType: 'runbook_steps',
          entityId: step.id,
          write: () => (delete(
            runbookSteps,
          )..where((tbl) => tbl.id.equals(step.id))).go(),
        );
      }

      for (final step in steps) {
        await db.recordUpsert(
          entityType: 'runbook_steps',
          entityId: step.id.value,
          write: () => into(runbookSteps).insert(step),
        );
      }
    });
  }
}
