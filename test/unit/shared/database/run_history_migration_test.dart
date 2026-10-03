import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late File dbFile;
  AppDatabase? db;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('run_history_migration');
    dbFile = File('${dir.path}/v15.db');
  });

  tearDown(() async {
    await db?.close();
    if (dbFile.existsSync()) {
      dbFile.deleteSync();
      dbFile.parent.deleteSync();
    }
  });

  test('v15 to v16 adds run history and the runbook policy columns', () async {
    final raw = sqlite3.open(dbFile.path);
    raw.execute('''
      CREATE TABLE "workspaces" (
        "id" TEXT NOT NULL PRIMARY KEY,
        "name" TEXT NOT NULL,
        "color_code" TEXT NULL,
        "created_at" INTEGER NOT NULL
      );
      CREATE TABLE "runbooks" (
        "id" TEXT NOT NULL PRIMARY KEY,
        "workspace_id" TEXT NOT NULL,
        "title" TEXT NOT NULL,
        "description" TEXT NULL,
        "created_at" INTEGER NOT NULL
      );
      CREATE TABLE "runbook_steps" (
        "id" TEXT NOT NULL PRIMARY KEY,
        "runbook_id" TEXT NOT NULL,
        "step_order" INTEGER NOT NULL,
        "command" TEXT NOT NULL,
        "expected_exit_code" INTEGER NOT NULL DEFAULT 0,
        "expected_output_pattern" TEXT NULL,
        "timeout_seconds" INTEGER NOT NULL DEFAULT 30
      );
      INSERT INTO workspaces (id, name, created_at)
        VALUES ('default', 'Default Workspace', 1600000000);
      INSERT INTO runbooks (id, workspace_id, title, created_at)
        VALUES ('rb', 'default', 'Deploy', 1600000000);
      INSERT INTO runbook_steps (id, runbook_id, step_order, command)
        VALUES ('s1', 'rb', 1, 'uptime');
      PRAGMA user_version = 15;
    ''');
    raw.close();

    final appDb = AppDatabase(NativeDatabase(dbFile));
    db = appDb;
    expect(appDb.schemaVersion, 17);

    // Existing rows take the defaults: no default targets, the old behaviour.
    final runbook = (await appDb.runbooksDao.getAllRunbooks()).single;
    expect(runbook.defaultHostIds, isNull);
    final step = (await appDb.runbooksDao.getStepsForRunbook('rb')).single;
    expect(step.onFailure, 'stop');
    expect(step.retries, 0);

    // The history tables exist and cascade.
    await appDb.runHistoryDao.insertRun(
      RunbookRunsCompanion.insert(
        id: 'r1',
        workspaceId: 'default',
        runbookId: const Value('rb'),
        kind: 'runbook',
        title: 'Deploy',
        strategy: 'parallel:4',
        startedAt: DateTime(2026),
        finishedAt: DateTime(2026),
        status: 'succeeded',
      ),
      [
        RunbookRunHostsCompanion.insert(
          id: 'rh1',
          runId: 'r1',
          position: 0,
          hostId: 'h',
          hostLabel: 'web',
          status: 'succeeded',
        ),
      ],
      [
        RunbookRunStepsCompanion.insert(
          id: 'rs1',
          runHostId: 'rh1',
          stepId: 's1',
          stepOrder: 1,
          command: 'uptime',
          status: 'success',
        ),
      ],
    );
    expect(await appDb.runHistoryDao.stepsForRun('r1'), hasLength(1));
  });

  test('v16 to v17 scrubs stored input values down to names', () async {
    final raw = sqlite3.open(dbFile.path);
    raw.execute('''
      CREATE TABLE "workspaces" (
        "id" TEXT NOT NULL PRIMARY KEY,
        "name" TEXT NOT NULL,
        "color_code" TEXT NULL,
        "created_at" INTEGER NOT NULL
      );
      CREATE TABLE "runbook_runs" (
        "id" TEXT NOT NULL PRIMARY KEY,
        "workspace_id" TEXT NOT NULL,
        "runbook_id" TEXT NULL,
        "kind" TEXT NOT NULL,
        "title" TEXT NOT NULL,
        "strategy" TEXT NOT NULL,
        "started_at" INTEGER NOT NULL,
        "finished_at" INTEGER NOT NULL,
        "status" TEXT NOT NULL,
        "variable_values" TEXT NOT NULL DEFAULT '{}'
      );
      CREATE TABLE "runbook_run_hosts" (
        "id" TEXT NOT NULL PRIMARY KEY,
        "run_id" TEXT NOT NULL,
        "position" INTEGER NOT NULL,
        "host_id" TEXT NOT NULL,
        "host_label" TEXT NOT NULL,
        "status" TEXT NOT NULL,
        "error" TEXT NULL
      );
      CREATE TABLE "runbook_run_steps" (
        "id" TEXT NOT NULL PRIMARY KEY,
        "run_host_id" TEXT NOT NULL,
        "step_id" TEXT NOT NULL,
        "step_order" INTEGER NOT NULL,
        "command" TEXT NOT NULL,
        "status" TEXT NOT NULL,
        "exit_code" INTEGER NULL,
        "attempts" INTEGER NOT NULL DEFAULT 1,
        "output" TEXT NOT NULL DEFAULT '',
        "output_truncated" INTEGER NOT NULL DEFAULT 0,
        "error" TEXT NULL,
        "duration_ms" INTEGER NULL
      );
      INSERT INTO workspaces (id, name, created_at)
        VALUES ('default', 'Default Workspace', 1600000000);
      INSERT INTO runbook_runs VALUES
        ('old', 'default', 'rb', 'runbook', 'Deploy', 'rolling', 1, 2,
         'succeeded', '{"token":"hunter2-s3cret","empty":""}'),
        ('new', 'default', 'rb', 'runbook', 'Deploy', 'rolling', 1, 2,
         'succeeded', '["token"]');
      INSERT INTO runbook_run_hosts VALUES
        ('oh', 'old', 0, 'h', 'web', 'succeeded', NULL),
        ('nh', 'new', 0, 'h', 'web', 'succeeded', NULL);
      INSERT INTO runbook_run_steps VALUES
        ('os', 'oh', 's1', 1, 'login hunter2-s3cret', 'success', 0, 1,
         'ok hunter2-s3cret', 0, 'bad hunter2-s3cret', 5),
        ('ns', 'nh', 's1', 1, 'login keepme', 'success', 0, 1,
         'ok', 0, NULL, 5);
      PRAGMA user_version = 16;
    ''');
    raw.close();

    final appDb = AppDatabase(NativeDatabase(dbFile));
    db = appDb;

    final runs = await appDb
        .customSelect('SELECT id, variable_values FROM runbook_runs')
        .get();
    final byId = {
      for (final r in runs)
        r.read<String>('id'): r.read<String>('variable_values'),
    };
    expect(jsonDecode(byId['old']!), ['empty', 'token']);
    expect(byId['new'], '["token"]');

    final step = await appDb
        .customSelect(
          "SELECT command, output, error FROM runbook_run_steps WHERE id = 'os'",
        )
        .getSingle();
    expect(step.read<String>('command'), r'login ${INPUT:token}');
    expect(step.read<String>('output'), 'ok [redacted]');
    expect(step.read<String?>('error'), 'bad [redacted]');

    // A row already in the new form is untouched.
    final untouched = await appDb
        .customSelect("SELECT command FROM runbook_run_steps WHERE id = 'ns'")
        .getSingle();
    expect(untouched.read<String>('command'), 'login keepme');
  });

  test('a fresh database has the same shape', () async {
    final appDb = AppDatabase(NativeDatabase.memory());
    db = appDb;
    final tables = await appDb
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name LIKE 'runbook_run%'",
        )
        .get();
    expect(tables.map((r) => r.read<String>('name')).toSet(), {
      'runbook_runs',
      'runbook_run_hosts',
      'runbook_run_steps',
    });
  });
}
