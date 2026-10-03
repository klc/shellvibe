import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/sync_journal.dart';
import 'package:shellvibe/core/sync/sync_row_codec.dart';
import 'package:shellvibe/core/sync/sync_row_writer.dart';
import 'package:shellvibe/features/snippets/data/repositories/run_history_repository.dart';
import 'package:shellvibe/features/snippets/data/repositories/runbooks_repository.dart';
import 'package:shellvibe/features/snippets/data/repositories/snippets_repository.dart';
import 'package:shellvibe/features/snippets/domain/models/active_run.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_step_model.dart';
import 'package:shellvibe/features/snippets/domain/models/snippet_model.dart';
import 'package:shellvibe/features/snippets/domain/models/variable_declaration.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('migration v17 to v18', () {
    late File dbFile;
    AppDatabase? db;

    setUp(() {
      final dir = Directory.systemTemp.createTempSync('v18_migration');
      dbFile = File('${dir.path}/v17.db');
    });

    tearDown(() async {
      await db?.close();
      if (dbFile.existsSync()) {
        dbFile.deleteSync();
        dbFile.parent.deleteSync();
      }
    });

    test('adds the columns and existing rows keep their meaning', () async {
      final raw = sqlite3.open(dbFile.path);
      raw.execute('''
        CREATE TABLE "workspaces" (
          "id" TEXT NOT NULL PRIMARY KEY, "name" TEXT NOT NULL,
          "color_code" TEXT NULL, "created_at" INTEGER NOT NULL);
        CREATE TABLE "snippets" (
          "id" TEXT NOT NULL PRIMARY KEY, "workspace_id" TEXT NOT NULL,
          "title" TEXT NOT NULL, "code" TEXT NOT NULL, "tags" TEXT NULL);
        CREATE TABLE "runbooks" (
          "id" TEXT NOT NULL PRIMARY KEY, "workspace_id" TEXT NOT NULL,
          "title" TEXT NOT NULL, "description" TEXT NULL,
          "created_at" INTEGER NOT NULL, "default_host_ids" TEXT NULL);
        CREATE TABLE "runbook_steps" (
          "id" TEXT NOT NULL PRIMARY KEY, "runbook_id" TEXT NOT NULL,
          "step_order" INTEGER NOT NULL, "command" TEXT NOT NULL,
          "expected_exit_code" INTEGER NOT NULL DEFAULT 0,
          "expected_output_pattern" TEXT NULL,
          "timeout_seconds" INTEGER NOT NULL DEFAULT 30,
          "on_failure" TEXT NOT NULL DEFAULT 'stop',
          "retries" INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE "runbook_runs" (
          "id" TEXT NOT NULL PRIMARY KEY, "workspace_id" TEXT NOT NULL,
          "runbook_id" TEXT NULL, "kind" TEXT NOT NULL,
          "title" TEXT NOT NULL, "strategy" TEXT NOT NULL,
          "started_at" INTEGER NOT NULL, "finished_at" INTEGER NOT NULL,
          "status" TEXT NOT NULL,
          "variable_values" TEXT NOT NULL DEFAULT '[]');
        INSERT INTO workspaces VALUES ('default', 'Default', NULL, 1);
        INSERT INTO snippets VALUES ('sn', 'default', 'Greet', 'echo hi', NULL);
        INSERT INTO runbooks (id, workspace_id, title, created_at)
          VALUES ('rb', 'default', 'Check', 1);
        INSERT INTO runbook_steps (id, runbook_id, step_order, command)
          VALUES ('s1', 'rb', 1, 'uptime');
        INSERT INTO runbook_runs VALUES
          ('r1', 'default', NULL, 'snippet', 'Greet', 'rolling', 1, 2,
           'succeeded', '[]');
        PRAGMA user_version = 17;
      ''');
      raw.close();

      final appDb = AppDatabase(NativeDatabase(dbFile));
      db = appDb;
      expect(appDb.schemaVersion, 18);

      final snippet = (await appDb.select(appDb.snippets).get()).single;
      expect(snippet.variables, isNull);
      final runbook = (await appDb.select(appDb.runbooks).get()).single;
      expect(runbook.variables, isNull);
      expect(runbook.tags, isNull);
      final step = (await appDb.select(appDb.runbookSteps).get()).single;
      expect(step.kind, 'command');
      expect(step.snippetId, isNull);
      expect(
        (await appDb.select(appDb.runbookRuns).get()).single.snippetId,
        isNull,
      );
    });
  });

  group('persistence', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test(
      'snippet variables round-trip; a secret never keeps a default',
      () async {
        final repo = SnippetsRepository(db.snippetsDao);
        await repo.addSnippet(
          SnippetModel(
            id: 'sn',
            workspaceId: 'default',
            title: 'Deploy',
            code: r'deploy ${INPUT:env} ${INPUT:token}',
            variables: const [
              VariableDeclaration(
                name: 'env',
                type: VariableType.enumeration,
                options: ['staging', 'prod'],
                defaultValue: 'staging',
                description: 'Where to',
              ),
              VariableDeclaration(
                name: 'token',
                type: VariableType.secret,
                defaultValue: 'leak',
                required: false,
              ),
            ],
          ),
        );
        final loaded = (await repo.getAllSnippets()).single.variables;
        expect(loaded.first.type, VariableType.enumeration);
        expect(loaded.first.options, ['staging', 'prod']);
        expect(loaded.first.defaultValue, 'staging');
        expect(loaded.first.description, 'Where to');
        expect(loaded.last.type, VariableType.secret);
        expect(loaded.last.required, isFalse);
        expect(loaded.last.defaultValue, isNull);
        final raw = (await db.select(db.snippets).get()).single.variables!;
        expect(raw, isNot(contains('leak')));
      },
    );

    test('runbook tags, variables and step kinds round-trip', () async {
      await db.snippetsDao.insertSnippet(
        SnippetsCompanion.insert(
          id: 'sn',
          workspaceId: 'default',
          title: 'Greet',
          code: 'echo hi',
        ),
      );
      final repo = RunbooksRepository(db.runbooksDao);
      await repo.addRunbook(
        RunbookModel(
          id: 'rb',
          workspaceId: 'default',
          title: 'Release',
          createdAt: DateTime(2026),
          tags: const ['ops', 'prod'],
          variables: const [VariableDeclaration(name: 'v', required: false)],
          steps: const [
            RunbookStepModel(
              id: 's1',
              runbookId: 'rb',
              stepOrder: 1,
              command: 'uptime',
            ),
            RunbookStepModel(
              id: 's2',
              runbookId: 'rb',
              stepOrder: 2,
              command: '# snippet: Greet',
              kind: StepKind.snippet,
              snippetId: 'sn',
            ),
            RunbookStepModel(
              id: 's3',
              runbookId: 'rb',
              stepOrder: 3,
              command: 'Check the dashboards',
              kind: StepKind.approval,
            ),
          ],
        ),
      );
      final loaded = (await repo.getAllRunbooks()).single;
      expect(loaded.tags, ['ops', 'prod']);
      expect(loaded.variables.single.required, isFalse);
      expect(loaded.steps.map((s) => s.kind), [
        StepKind.command,
        StepKind.snippet,
        StepKind.approval,
      ]);
      expect(loaded.steps[1].snippetId, 'sn');
    });

    test(
      'deleting a snippet clears step references and journals them',
      () async {
        await db.snippetsDao.insertSnippet(
          SnippetsCompanion.insert(
            id: 'sn',
            workspaceId: 'default',
            title: 'Greet',
            code: 'echo hi',
          ),
        );
        await db.runbooksDao.insertRunbook(
          RunbooksCompanion.insert(
            id: 'rb',
            workspaceId: 'default',
            title: 'R',
            createdAt: DateTime(2026),
          ),
        );
        await db.runbooksDao.replaceSteps('rb', [
          RunbookStepsCompanion.insert(
            id: 's1',
            runbookId: 'rb',
            stepOrder: 1,
            command: '# snippet: Greet',
            kind: const Value('snippet'),
            snippetId: const Value('sn'),
          ),
        ]);
        db.syncJournal = SyncJournal(db: db);

        await db.snippetsDao.deleteSnippet('sn');

        final step = (await db.select(db.runbookSteps).get()).single;
        expect(step.snippetId, isNull);
        expect(step.kind, 'snippet');
        final recorded = (await SyncJournal(db: db).pending())
            .map((o) => '${o.entityType}/${o.entityId}:${o.operation}')
            .toList();
        expect(recorded, contains('runbook_steps/s1:upsert'));
        expect(
          SyncJournal.setNulls['snippets'],
          contains(('runbook_steps', 'snippet_id')),
        );
      },
    );

    test(
      'a snippet run is stored with its snippet id and listed per snippet',
      () async {
        final repo = RunHistoryRepository(db.runHistoryDao);
        ActiveRun run(String snippetId) => ActiveRun(
          runbook: RunbookModel(
            id: 'snippet:$snippetId',
            workspaceId: 'default',
            title: 'S $snippetId',
            createdAt: DateTime(2026),
            steps: [
              RunbookStepModel(
                id: 'st',
                runbookId: 'snippet:$snippetId',
                stepOrder: 1,
                command: 'x',
              ),
            ],
          ),
          running: false,
          startedAt: DateTime(2026),
          finishedAt: DateTime(2026),
          hosts: const [],
        );
        await repo.save(run('a'));
        await repo.save(run('a'));
        await repo.save(run('b'));

        expect(await repo.forSnippet('a'), hasLength(2));
        expect(await repo.forSnippet('b'), hasLength(1));
        await repo.clear(snippetId: 'a');
        expect(await repo.forSnippet('a'), isEmpty);
        expect(await repo.forSnippet('b'), hasLength(1));
      },
    );
  });

  group('sync', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('rows from an older client decode with the defaults', () async {
      await SyncRowWriter.write(db, 'snippets', {
        'id': 'sn',
        'workspaceId': 'default',
        'title': 'Old',
        'code': 'x',
      });
      await SyncRowWriter.write(db, 'runbooks', {
        'id': 'rb',
        'workspaceId': 'default',
        'title': 'Old',
        'createdAt': DateTime(2026).toIso8601String(),
      });
      await SyncRowWriter.write(db, 'runbook_steps', {
        'id': 's1',
        'runbookId': 'rb',
        'stepOrder': 1,
        'command': 'uptime',
      });
      expect((await db.select(db.snippets).get()).single.variables, isNull);
      final rb = (await db.select(db.runbooks).get()).single;
      expect(rb.variables, isNull);
      expect(rb.tags, isNull);
      final step = (await db.select(db.runbookSteps).get()).single;
      expect(step.kind, 'command');
      expect(step.snippetId, isNull);
    });

    test('the new fields are encoded and written back', () async {
      await db.snippetsDao.insertSnippet(
        SnippetsCompanion.insert(
          id: 'sn',
          workspaceId: 'default',
          title: 'Greet',
          code: 'echo hi',
          variables: const Value('[{"name":"x"}]'),
        ),
      );
      await db.runbooksDao.insertRunbook(
        RunbooksCompanion.insert(
          id: 'rb',
          workspaceId: 'default',
          title: 'R',
          createdAt: DateTime(2026),
          tags: const Value('["ops"]'),
          variables: const Value('[{"name":"y"}]'),
        ),
      );
      await db.runbooksDao.replaceSteps('rb', [
        RunbookStepsCompanion.insert(
          id: 's1',
          runbookId: 'rb',
          stepOrder: 1,
          command: 'Wait',
          kind: const Value('approval'),
        ),
        RunbookStepsCompanion.insert(
          id: 's2',
          runbookId: 'rb',
          stepOrder: 2,
          command: '# snippet: Greet',
          kind: const Value('snippet'),
          snippetId: const Value('sn'),
        ),
      ]);

      final snippet = SyncRowCodec.snippet(
        (await db.select(db.snippets).get()).single,
      );
      final runbook = SyncRowCodec.runbook(
        (await db.select(db.runbooks).get()).single,
      );
      final steps = [
        for (final s in await db.select(db.runbookSteps).get())
          SyncRowCodec.runbookStep(s),
      ];
      expect(snippet['variables'], '[{"name":"x"}]');
      expect(runbook['tags'], '["ops"]');
      expect(runbook['variables'], '[{"name":"y"}]');
      expect(steps.map((s) => s['kind']).toSet(), {'approval', 'snippet'});

      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await SyncRowWriter.write(other, 'snippets', snippet);
      await SyncRowWriter.write(other, 'runbooks', runbook);
      for (final s in steps) {
        await SyncRowWriter.write(other, 'runbook_steps', s);
      }
      final rb = (await other.select(other.runbooks).get()).single;
      expect(rb.tags, '["ops"]');
      final back = await other.select(other.runbookSteps).get();
      expect(back.firstWhere((s) => s.id == 's2').snippetId, 'sn');
    });
  });
}
