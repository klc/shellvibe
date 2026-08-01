import 'package:drift/drift.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/runbooks_dao.dart';
import '../../domain/models/runbook_model.dart';
import '../../domain/models/runbook_step_model.dart';

class RunbooksRepository {
  final RunbooksDao _dao;

  RunbooksRepository(this._dao);

  Future<List<RunbookModel>> getAllRunbooks() async {
    final runbooks = await _dao.getAllRunbooks();
    return _loadModels(runbooks);
  }

  Future<List<RunbookModel>> getRunbooksByWorkspace(String workspaceId) async {
    final runbooks = await _dao.getRunbooksByWorkspace(workspaceId);
    return _loadModels(runbooks);
  }

  Future<List<RunbookModel>> _loadModels(List<Runbook> runbooks) async {
    final results = <RunbookModel>[];
    for (final r in runbooks) {
      final steps = await _dao.getStepsForRunbook(r.id);
      results.add(_mapToModel(r, steps));
    }
    return results;
  }

  Stream<List<RunbookModel>> watchAllRunbooks() {
    return _dao.watchAllRunbooks().asyncMap((runbooks) async {
      final results = <RunbookModel>[];
      for (final r in runbooks) {
        final steps = await _dao.getStepsForRunbook(r.id);
        results.add(_mapToModel(r, steps));
      }
      return results;
    });
  }

  Future<void> addRunbook(RunbookModel runbook) async {
    final companion = RunbooksCompanion.insert(
      id: runbook.id,
      workspaceId: runbook.workspaceId,
      title: runbook.title,
      description: Value(runbook.description),
      createdAt: runbook.createdAt,
    );
    await _dao.insertRunbook(companion);

    final stepCompanions = runbook.steps
        .map(
          (s) => RunbookStepsCompanion.insert(
            id: s.id,
            runbookId: runbook.id,
            stepOrder: s.stepOrder,
            command: s.command,
            expectedExitCode: Value(s.expectedExitCode),
            expectedOutputPattern: Value(s.expectedOutputPattern),
            timeoutSeconds: Value(s.timeoutSeconds),
          ),
        )
        .toList();
    await _dao.replaceSteps(runbook.id, stepCompanions);
  }

  Future<void> updateRunbook(RunbookModel runbook) async {
    final companion = RunbooksCompanion(
      id: Value(runbook.id),
      workspaceId: Value(runbook.workspaceId),
      title: Value(runbook.title),
      description: Value(runbook.description),
      createdAt: Value(runbook.createdAt),
    );
    await _dao.updateRunbook(companion);

    final stepCompanions = runbook.steps
        .map(
          (s) => RunbookStepsCompanion.insert(
            id: s.id,
            runbookId: runbook.id,
            stepOrder: s.stepOrder,
            command: s.command,
            expectedExitCode: Value(s.expectedExitCode),
            expectedOutputPattern: Value(s.expectedOutputPattern),
            timeoutSeconds: Value(s.timeoutSeconds),
          ),
        )
        .toList();
    await _dao.replaceSteps(runbook.id, stepCompanions);
  }

  Future<void> deleteRunbook(String id) async {
    await _dao.deleteRunbook(id);
  }

  RunbookModel _mapToModel(Runbook r, List<RunbookStep> steps) {
    return RunbookModel(
      id: r.id,
      workspaceId: r.workspaceId,
      title: r.title,
      description: r.description,
      createdAt: r.createdAt,
      steps: steps
          .map(
            (s) => RunbookStepModel(
              id: s.id,
              runbookId: s.runbookId,
              stepOrder: s.stepOrder,
              command: s.command,
              expectedExitCode: s.expectedExitCode,
              expectedOutputPattern: s.expectedOutputPattern,
              timeoutSeconds: s.timeoutSeconds,
            ),
          )
          .toList(),
    );
  }
}
