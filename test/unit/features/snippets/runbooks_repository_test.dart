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
    test('Initial runbooks list is empty', () async {
      final runbooks = await repository.getAllRunbooks();
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

      final runbooks = await repository.getAllRunbooks();
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
      expect((await repository.getAllRunbooks()).length, equals(1));

      await repository.deleteRunbook('rb_1');
      expect(await repository.getAllRunbooks(), isEmpty);
    });
  });
}
