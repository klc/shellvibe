import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/sync_journal.dart';
import 'package:shellvibe/core/sync/sync_row_codec.dart';
import 'package:shellvibe/core/sync/sync_row_writer.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Startup snippets (hosts, template panes) and a template's on-open runbook
/// are nullable references: deleting what they point at must clear them, and
/// that clearing has to reach other devices.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('schema v17', () {
    late File dbFile;
    AppDatabase? db;

    setUp(() {
      final dir = Directory.systemTemp.createTempSync('v17_migration');
      dbFile = File('${dir.path}/v16.db');
    });

    tearDown(() async {
      await db?.close();
      if (dbFile.existsSync()) {
        dbFile.deleteSync();
        dbFile.parent.deleteSync();
      }
    });

    test('v16 to v17 adds the reference columns with their defaults', () async {
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
        CREATE TABLE "hosts" (
          "id" TEXT NOT NULL PRIMARY KEY, "workspace_id" TEXT NOT NULL,
          "group_id" TEXT NULL, "identity_id" TEXT NULL,
          "label" TEXT NOT NULL, "hostname" TEXT NOT NULL,
          "username" TEXT NULL, "port" INTEGER NOT NULL DEFAULT 22,
          "protocol" TEXT NOT NULL DEFAULT 'ssh',
          "mosh_server_path" TEXT NULL, "mosh_port_range" TEXT NULL,
          "color_tag" TEXT NULL, "jump_host_id" TEXT NULL,
          "created_at" INTEGER NOT NULL,
          "environment" TEXT NOT NULL DEFAULT 'dev',
          "mcp_visible" INTEGER NOT NULL DEFAULT 1,
          "mcp_default_mode" TEXT NOT NULL DEFAULT 'readonly');
        CREATE TABLE "templates" (
          "id" TEXT NOT NULL PRIMARY KEY, "workspace_id" TEXT NOT NULL,
          "name" TEXT NOT NULL, "description" TEXT NULL,
          "active_pane_id" TEXT NULL, "created_at" INTEGER NOT NULL);
        CREATE TABLE "template_panes" (
          "id" TEXT NOT NULL PRIMARY KEY, "template_id" TEXT NOT NULL,
          "pane_order" INTEGER NOT NULL, "parent_pane_id" TEXT NULL,
          "split_direction" TEXT NULL,
          "split_ratio" REAL NOT NULL DEFAULT 0.5,
          "session_type" TEXT NOT NULL, "host_id" TEXT NULL,
          "title" TEXT NULL);
        INSERT INTO workspaces VALUES ('default', 'Default', NULL, 1);
        INSERT INTO hosts (id, workspace_id, label, hostname, created_at)
          VALUES ('h', 'default', 'web', 'web.example.com', 1);
        INSERT INTO templates VALUES ('t', 'default', 'Layout', NULL, NULL, 1);
        INSERT INTO template_panes (id, template_id, pane_order, session_type)
          VALUES ('p', 't', 0, 'ssh');
        PRAGMA user_version = 16;
      ''');
      raw.close();

      final appDb = AppDatabase(NativeDatabase(dbFile));
      db = appDb;
      expect(appDb.schemaVersion, 18);

      final host = (await appDb.select(appDb.hosts).get()).single;
      expect(host.startupSnippetId, isNull);
      final template = (await appDb.select(appDb.templates).get()).single;
      expect(template.onOpenRunbookId, isNull);
      expect(template.onOpenConfirm, isTrue);
      final pane = (await appDb.select(appDb.templatePanes).get()).single;
      expect(pane.startupSnippetId, isNull);
    });
  });

  group('deleting what is referenced', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
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
          title: 'Check',
          createdAt: DateTime(2026),
        ),
      );
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'h',
          workspaceId: 'default',
          label: 'web',
          hostname: 'web.example.com',
          createdAt: DateTime(2026),
          startupSnippetId: const Value('sn'),
        ),
      );
      await db.templatesDao.insertTemplate(
        TemplatesCompanion.insert(
          id: 't',
          workspaceId: 'default',
          name: 'Layout',
          createdAt: DateTime(2026),
          onOpenRunbookId: const Value('rb'),
        ),
      );
      await db.templatesDao.replacePanes('t', [
        TemplatePanesCompanion.insert(
          id: 'p',
          templateId: 't',
          paneOrder: 0,
          sessionType: 'ssh',
          startupSnippetId: const Value('sn'),
        ),
      ]);
      db.syncJournal = SyncJournal(db: db);
    });

    tearDown(() => db.close());

    Future<List<String>> recorded() async =>
        (await SyncJournal(db: db).pending())
            .map((o) => '${o.entityType}/${o.entityId}:${o.operation}')
            .toList();

    test('deleting a snippet clears host and pane references', () async {
      await db.snippetsDao.deleteSnippet('sn');
      expect((await db.select(db.hosts).get()).single.startupSnippetId, isNull);
      expect(
        (await db.select(db.templatePanes).get()).single.startupSnippetId,
        isNull,
      );
      // Both rows survive.
      expect(await db.select(db.hosts).get(), hasLength(1));
      expect(await db.select(db.templatePanes).get(), hasLength(1));
    });

    test('and the clearing is journaled so it syncs', () async {
      await db.snippetsDao.deleteSnippet('sn');
      expect(
        await recorded(),
        containsAll([
          'snippets/sn:delete',
          'hosts/h:upsert',
          'template_panes/p:upsert',
        ]),
      );
    });

    test('deleting a runbook clears the template on-open reference', () async {
      await db.runbooksDao.deleteRunbook('rb');
      final template = (await db.select(db.templates).get()).single;
      expect(template.onOpenRunbookId, isNull);
      expect(
        await recorded(),
        containsAll(['runbooks/rb:delete', 'templates/t:upsert']),
      );
    });

    test('SyncJournal.setNulls mirrors the schema', () {
      expect(
        SyncJournal.setNulls['snippets'],
        contains(('hosts', 'startup_snippet_id')),
      );
      expect(
        SyncJournal.setNulls['snippets'],
        contains(('template_panes', 'startup_snippet_id')),
      );
      expect(
        SyncJournal.setNulls['runbooks'],
        contains(('templates', 'on_open_runbook_id')),
      );
    });
  });

  group('sync encoding', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('snippets sort ahead of hosts so a reference is never early', () {
      final types = SyncRowCodec.syncableTypes;
      expect(types.indexOf('snippets'), lessThan(types.indexOf('hosts')));
      expect(types.indexOf('runbooks'), lessThan(types.indexOf('templates')));
      expect(
        types.indexOf('snippets'),
        lessThan(types.indexOf('template_panes')),
      );
    });

    test('the new fields are encoded', () async {
      await db.snippetsDao.insertSnippet(
        SnippetsCompanion.insert(
          id: 'sn',
          workspaceId: 'default',
          title: 'Greet',
          code: 'echo hi',
        ),
      );
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'h',
          workspaceId: 'default',
          label: 'web',
          hostname: 'web',
          createdAt: DateTime(2026),
          startupSnippetId: const Value('sn'),
        ),
      );
      final host = SyncRowCodec.host((await db.select(db.hosts).get()).single);
      expect(host['startupSnippetId'], 'sn');
    });

    test('rows from an older client decode with the defaults', () async {
      final template = await SyncRowWriter.write(db, 'templates', {
        'id': 't',
        'workspaceId': 'default',
        'name': 'Old',
        'createdAt': DateTime(2026).toIso8601String(),
      });
      final pane = await SyncRowWriter.write(db, 'template_panes', {
        'id': 'p',
        'templateId': 't',
        'paneOrder': 0,
        'sessionType': 'ssh',
      });
      final host = await SyncRowWriter.write(db, 'hosts', {
        'id': 'h',
        'workspaceId': 'default',
        'label': 'web',
        'hostname': 'web',
        'createdAt': DateTime(2026).toIso8601String(),
      });
      expect(template.written && pane.written && host.written, isTrue);

      final t = (await db.select(db.templates).get()).single;
      expect(t.onOpenRunbookId, isNull);
      expect(t.onOpenConfirm, isTrue);
      expect(
        (await db.select(db.templatePanes).get()).single.startupSnippetId,
        isNull,
      );
      expect((await db.select(db.hosts).get()).single.startupSnippetId, isNull);
    });

    test(
      'a reference to a row that is not here is cleared, not fatal',
      () async {
        final host = await SyncRowWriter.write(db, 'hosts', {
          'id': 'h',
          'workspaceId': 'default',
          'label': 'web',
          'hostname': 'web',
          'createdAt': DateTime(2026).toIso8601String(),
          'startupSnippetId': 'missing',
        });
        expect(host.written, isTrue);
        expect(host.clearedReferences, ['startup snippet']);
        expect(
          (await db.select(db.hosts).get()).single.startupSnippetId,
          isNull,
        );
      },
    );

    test('a present reference is kept', () async {
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
          title: 'Check',
          createdAt: DateTime(2026),
        ),
      );
      await SyncRowWriter.write(db, 'hosts', {
        'id': 'h',
        'workspaceId': 'default',
        'label': 'web',
        'hostname': 'web',
        'createdAt': DateTime(2026).toIso8601String(),
        'startupSnippetId': 'sn',
      });
      await SyncRowWriter.write(db, 'templates', {
        'id': 't',
        'workspaceId': 'default',
        'name': 'T',
        'createdAt': DateTime(2026).toIso8601String(),
        'onOpenRunbookId': 'rb',
        'onOpenConfirm': false,
        'someFutureField': 1,
      });
      expect((await db.select(db.hosts).get()).single.startupSnippetId, 'sn');
      final t = (await db.select(db.templates).get()).single;
      expect(t.onOpenRunbookId, 'rb');
      expect(t.onOpenConfirm, isFalse);
    });
  });
}
