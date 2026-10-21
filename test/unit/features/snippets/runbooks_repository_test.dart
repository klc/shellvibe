import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/snippets/data/repositories/runbooks_repository.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_step_model.dart';
import 'package:shellvibe/shared/database/app_database.dart';

void main() {
  late AppDatabase db;
  late RunbooksRepository repository;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'ws_1',
        name: 'Default Workspace',
        createdAt: DateTime.now(),
      ),
    );
    repository = RunbooksRepository(db.runbooksDao);
  });

  tearDown(() async {
    await db.close();
  });

  group('RunbooksRepository Unit Tests', () {
    test('getAllRunbooks spans workspaces and loads steps', () async {
      await db.workspacesDao.insertWorkspace(
        WorkspacesCompanion.insert(
          id: 'ws_2',
          name: 'Other',
          createdAt: DateTime.now(),
        ),
      );
      for (final (id, ws) in [('rb_1', 'ws_1'), ('rb_2', 'ws_2')]) {
        await repository.addRunbook(
          RunbookModel(
            id: id,
            workspaceId: ws,
            title: id,
            createdAt: DateTime.now(),
            steps: [
              RunbookStepModel(
                id: 's_$id',
                runbookId: id,
                stepOrder: 1,
                command: 'ls',
              ),
            ],
          ),
        );
      }

      final all = await repository.getAllRunbooks();

      expect(all.map((r) => r.id), unorderedEquals(['rb_1', 'rb_2']));
      expect(all.every((r) => r.steps.length == 1), isTrue);
    });

    test('step policy and default targets round-trip', () async {
      await repository.addRunbook(
        RunbookModel(
          id: 'rb_p',
          workspaceId: 'ws_1',
          title: 'Policy',
          createdAt: DateTime.now(),
          defaultHostIds: const ['h1', 'h2'],
          steps: const [
            RunbookStepModel(
              id: 's1',
              runbookId: 'rb_p',
              stepOrder: 1,
              command: 'a',
              onFailure: StepFailurePolicy.continueRun,
              retries: 4,
            ),
            RunbookStepModel(
              id: 's2',
              runbookId: 'rb_p',
              stepOrder: 2,
              command: 'b',
            ),
          ],
        ),
      );
      var loaded = (await repository.getRunbooksByWorkspace('ws_1')).single;
      expect(loaded.defaultHostIds, ['h1', 'h2']);
      expect(loaded.steps[0].onFailure, StepFailurePolicy.continueRun);
      expect(loaded.steps[0].retries, 4);
      expect(loaded.steps[1].onFailure, StepFailurePolicy.stop);
      expect(loaded.steps[1].retries, 0);

      await repository.setDefaultHostIds('rb_p', ['h3']);
      loaded = (await repository.getRunbooksByWorkspace('ws_1')).single;
      expect(loaded.defaultHostIds, ['h3']);
      // Only the defaults changed.
      expect(loaded.steps, hasLength(2));

      await repository.setDefaultHostIds('rb_p', []);
      expect(
        (await repository.getRunbooksByWorkspace('ws_1')).single.defaultHostIds,
        isEmpty,
      );
    });

    test('Initial runbooks list is empty', () async {
      final runbooks = await repository.getRunbooksByWorkspace('ws_1');
      expect(runbooks, isEmpty);
    });

    test('addRunbook saves runbook with ordered steps', () async {
      final runbook = RunbookModel(
        id: 'rb_1',
        workspaceId: 'ws_1',
        title: 'CI/CD Pipeline',
        description: 'Build and deploy pipeline',
        createdAt: DateTime.now(),
        steps: const [
          RunbookStepModel(
            id: 'step_1',
            runbookId: 'rb_1',
            stepOrder: 1,
            command: 'git pull',
          ),
          RunbookStepModel(
            id: 'step_2',
            runbookId: 'rb_1',
            stepOrder: 2,
            command: 'make build',
          ),
        ],
      );

      await repository.addRunbook(runbook);

      final runbooks = await repository.getRunbooksByWorkspace('ws_1');
      expect(runbooks.length, equals(1));
      expect(runbooks.first.title, equals('CI/CD Pipeline'));
      expect(runbooks.first.steps.length, equals(2));
      expect(runbooks.first.steps.first.command, equals('git pull'));
      expect(runbooks.first.steps.last.command, equals('make build'));
    });

    test('deleteRunbook removes runbook and associated steps', () async {
      final runbook = RunbookModel(
        id: 'rb_1',
        workspaceId: 'ws_1',
        title: 'To Delete',
        createdAt: DateTime.now(),
        steps: const [
          RunbookStepModel(
            id: 's_1',
            runbookId: 'rb_1',
            stepOrder: 1,
            command: 'echo 1',
          ),
        ],
      );

      await repository.addRunbook(runbook);
      expect(
        (await repository.getRunbooksByWorkspace('ws_1')).length,
        equals(1),
      );

      await repository.deleteRunbook('rb_1');
      expect(await repository.getRunbooksByWorkspace('ws_1'), isEmpty);
    });
  });
}
