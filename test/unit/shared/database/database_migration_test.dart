import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:terly2/shared/database/app_database.dart';

void main() {
  late File tempDbFile;
  AppDatabase? db;

  setUp(() {
    final tempDir = Directory.systemTemp.createTempSync('drift_migration_test');
    tempDbFile = File('${tempDir.path}/migration_v1_to_v2.db');
  });

  tearDown(() async {
    await db?.close();
    if (tempDbFile.existsSync()) {
      tempDbFile.deleteSync();
      tempDbFile.parent.deleteSync();
    }
  });

  group('AppDatabase Migration Tests', () {
    test('upgrading schema from v1 to v2 adds username column to hosts cleanly', () async {
      // 1. Initialize a SQLite database file at schema version 1 without the username column in hosts.
      final rawDb = sqlite3.open(tempDbFile.path);
      rawDb.execute('PRAGMA foreign_keys = ON;');
      rawDb.execute('''
        CREATE TABLE IF NOT EXISTS "workspaces" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "name" TEXT NOT NULL,
          "color_code" TEXT NULL,
          "created_at" INTEGER NOT NULL
        );
      ''');
      rawDb.execute('''
        CREATE TABLE IF NOT EXISTS "hosts" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "workspace_id" TEXT NOT NULL,
          "group_id" TEXT NULL,
          "identity_id" TEXT NULL,
          "label" TEXT NOT NULL,
          "hostname" TEXT NOT NULL,
          "port" INTEGER NOT NULL DEFAULT 22,
          "protocol" TEXT NOT NULL DEFAULT 'ssh',
          "color_tag" TEXT NULL,
          "jump_host_id" TEXT NULL,
          "created_at" INTEGER NOT NULL
        );
      ''');
      rawDb.execute('PRAGMA user_version = 1;');
      rawDb.execute('''
        INSERT INTO workspaces (id, name, created_at)
        VALUES ('ws-1', 'Default Workspace', 1600000000);
      ''');
      rawDb.execute('''
        INSERT INTO hosts (id, workspace_id, label, hostname, port, protocol, created_at)
        VALUES ('host-v1', 'ws-1', 'Legacy Host', '10.0.0.1', 22, 'ssh', 1600000000);
      ''');
      rawDb.dispose();

      // 2. Open the database using AppDatabase (which is at schemaVersion 2).
      final appDb = AppDatabase(NativeDatabase(tempDbFile));
      db = appDb;

      expect(appDb.schemaVersion, equals(2));

      // 3. Verify existing legacy host record can be fetched.
      final fetchedHost = await appDb.hostsDao.getHostById('host-v1');
      expect(fetchedHost, isNotNull);
      expect(fetchedHost!.label, equals('Legacy Host'));
      expect(fetchedHost.username, isNull);

      // 4. Verify update operation with username column succeeds without SqliteException(1): no such column: username.
      await appDb.hostsDao.updateHost(
        fetchedHost.copyWith(username: Value('admin')),
      );

      final updatedHost = await appDb.hostsDao.getHostById('host-v1');
      expect(updatedHost, isNotNull);
      expect(updatedHost!.username, equals('admin'));

      // 5. Verify inserting a new host with username works properly.
      await appDb.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'host-v2',
          workspaceId: 'ws-1',
          label: 'New Host v2',
          hostname: '10.0.0.2',
          username: const Value('root'),
          createdAt: DateTime.now(),
        ),
      );

      final newHost = await appDb.hostsDao.getHostById('host-v2');
      expect(newHost, isNotNull);
      expect(newHost!.username, equals('root'));
    });
  });
}
