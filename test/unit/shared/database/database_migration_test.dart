import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:shellvibe/shared/database/app_database.dart';

/// The `hosts` table as it stood at schema v2: after `username` was added and
/// before the v5 Mosh columns. Fixtures that start at v2 or later need it,
/// because the migrations from there on alter this table.
const _hostsTableAtV2 = '''
  CREATE TABLE IF NOT EXISTS "hosts" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "workspace_id" TEXT NOT NULL,
    "group_id" TEXT NULL,
    "identity_id" TEXT NULL,
    "label" TEXT NOT NULL,
    "hostname" TEXT NOT NULL,
    "username" TEXT NULL,
    "port" INTEGER NOT NULL DEFAULT 22,
    "protocol" TEXT NOT NULL DEFAULT 'ssh',
    "color_tag" TEXT NULL,
    "jump_host_id" TEXT NULL,
    "created_at" INTEGER NOT NULL
  );
''';

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
    test(
      'upgrading schema from v1 to v2 adds username column to hosts cleanly',
      () async {
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
        rawDb.close();

        // 2. Open the database using AppDatabase, which runs every migration
        // from v1 up to the current schema version.
        final appDb = AppDatabase(NativeDatabase(tempDbFile));
        db = appDb;

        expect(appDb.schemaVersion, equals(8));

        // 3. Verify existing legacy host record can be fetched.
        final fetchedHost = await appDb.hostsDao.getHostById('host-v1');
        expect(fetchedHost, isNotNull);
        expect(fetchedHost!.label, equals('Legacy Host'));
        expect(fetchedHost.username, isNull);

        // 4. Verify update operation with username column succeeds without SqliteException(1): no such column: username.
        await appDb.hostsDao.updateHostById(
          'host-v1',
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
      },
    );

    test('upgrading to v3 rewrites double-encoded known_hosts fingerprints', () async {
      const plainFingerprint =
          'SHA256:5FSkiWFrH2mFbfCzXhAv9k3PPWQiJRuVpH2vhcaGZ6c';
      final legacyValue = base64.encode(utf8.encode(plainFingerprint));

      final rawDb = sqlite3.open(tempDbFile.path);
      // A real v2 database always carries hosts; the later migrations alter it.
      rawDb.execute(_hostsTableAtV2);
      rawDb.execute('''
        CREATE TABLE IF NOT EXISTS "known_hosts" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "hostname" TEXT NOT NULL,
          "port" INTEGER NOT NULL DEFAULT 22,
          "key_type" TEXT NOT NULL,
          "fingerprint_sha256" TEXT NOT NULL,
          "first_seen_at" INTEGER NOT NULL
        );
      ''');
      rawDb.execute('PRAGMA user_version = 2;');
      rawDb.execute(
        'INSERT INTO known_hosts (id, hostname, port, key_type, fingerprint_sha256, first_seen_at) '
        "VALUES ('kh-legacy', 'legacy.example.com', 22, 'ssh-ed25519', '$legacyValue', 1600000000);",
      );
      // A value that is not legacy-encoded must survive untouched.
      rawDb.execute(
        'INSERT INTO known_hosts (id, hostname, port, key_type, fingerprint_sha256, first_seen_at) '
        "VALUES ('kh-new', 'new.example.com', 22, 'ssh-ed25519', '$plainFingerprint', 1600000000);",
      );
      rawDb.close();

      final appDb = AppDatabase(NativeDatabase(tempDbFile));
      db = appDb;

      final migrated = await appDb.knownHostsDao.findKnownHost(
        'legacy.example.com',
        22,
      );
      expect(migrated, isNotNull);
      expect(migrated!.fingerprintSha256, equals(plainFingerprint));

      final untouched = await appDb.knownHostsDao.findKnownHost(
        'new.example.com',
        22,
      );
      expect(untouched, isNotNull);
      expect(untouched!.fingerprintSha256, equals(plainFingerprint));
    });

    test('upgrading to v4 creates usable template tables', () async {
      final rawDb = sqlite3.open(tempDbFile.path);
      rawDb.execute('''
        CREATE TABLE IF NOT EXISTS "workspaces" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "name" TEXT NOT NULL,
          "color_code" TEXT NULL,
          "created_at" INTEGER NOT NULL
        );
      ''');
      rawDb.execute(_hostsTableAtV2);
      rawDb.execute('PRAGMA user_version = 3;');
      rawDb.execute('''
        INSERT INTO workspaces (id, name, created_at)
        VALUES ('ws-1', 'Default Workspace', 1600000000);
      ''');
      rawDb.close();

      final appDb = AppDatabase(NativeDatabase(tempDbFile));
      db = appDb;

      await appDb.templatesDao.insertTemplate(
        TemplatesCompanion.insert(
          id: 'tpl-1',
          workspaceId: 'ws-1',
          name: 'Morning check',
          createdAt: DateTime.now(),
        ),
      );
      await appDb.templatesDao.replacePanes('tpl-1', [
        TemplatePanesCompanion.insert(
          id: 'pane-1',
          templateId: 'tpl-1',
          paneOrder: 0,
          sessionType: 'local',
        ),
      ]);

      final templates = await appDb.templatesDao.getAllTemplates();
      expect(templates.map((t) => t.name), ['Morning check']);
      final panes = await appDb.templatesDao.getPanesForTemplate('tpl-1');
      expect(panes.single.sessionType, equals('local'));
      // Column default, so an older row shape stays readable.
      expect(panes.single.splitRatio, equals(0.5));
    });

    test(
      'upgrading to v5 adds the Mosh columns and keeps existing hosts',
      () async {
        final rawDb = sqlite3.open(tempDbFile.path);
        rawDb.execute('''
        CREATE TABLE IF NOT EXISTS "workspaces" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "name" TEXT NOT NULL,
          "color_code" TEXT NULL,
          "created_at" INTEGER NOT NULL
        );
      ''');
        rawDb.execute(_hostsTableAtV2);
        rawDb.execute('PRAGMA user_version = 4;');
        rawDb.execute('''
        INSERT INTO workspaces (id, name, created_at)
        VALUES ('ws-1', 'Default Workspace', 1600000000);
      ''');
        // A host already stored with protocol 'mosh' back when nothing
        // implemented it. The migration must leave that column alone.
        rawDb.execute('''
        INSERT INTO hosts (id, workspace_id, label, hostname, port, protocol, created_at)
        VALUES ('host-v4', 'ws-1', 'Old Mosh Host', '10.0.0.9', 22, 'mosh', 1600000000);
      ''');
        rawDb.close();

        final appDb = AppDatabase(NativeDatabase(tempDbFile));
        db = appDb;

        final migrated = await appDb.hostsDao.getHostById('host-v4');
        expect(migrated, isNotNull);
        expect(migrated!.protocol, equals('mosh'));
        // Nullable, so an existing host falls back to the mosh defaults.
        expect(migrated.moshServerPath, isNull);
        expect(migrated.moshPortRange, isNull);

        await appDb.hostsDao.updateHostById(
          'host-v4',
          migrated.copyWith(
            moshServerPath: const Value('/opt/bin/mosh-server'),
            moshPortRange: const Value('61000:61010'),
          ),
        );

        final updated = await appDb.hostsDao.getHostById('host-v4');
        expect(updated!.moshServerPath, equals('/opt/bin/mosh-server'));
        expect(updated.moshPortRange, equals('61000:61010'));
      },
    );

    test('upgrading to v6 creates the paired devices table', () async {
      final rawDb = sqlite3.open(tempDbFile.path);
      rawDb.execute(_hostsTableAtV2);
      rawDb.execute(
        'ALTER TABLE hosts ADD COLUMN "mosh_server_path" TEXT NULL;',
      );
      rawDb.execute(
        'ALTER TABLE hosts ADD COLUMN "mosh_port_range" TEXT NULL;',
      );
      rawDb.execute('PRAGMA user_version = 5;');
      rawDb.close();

      final appDb = AppDatabase(NativeDatabase(tempDbFile));
      db = appDb;

      expect(await appDb.pairedDevicesDao.getAll(), isEmpty);
      final now = DateTime.utc(2026, 8, 9, 12);
      await appDb.pairedDevicesDao.upsert(
        PairedDevicesCompanion.insert(
          id: 'phone-1',
          name: 'iPhone 15',
          platform: 'ios',
          secretHash: 'argon2id-v1:test',
          publicKey: 'phone-public-key',
          pairedAt: now,
          lastSeenAt: now,
        ),
      );

      final devices = await appDb.pairedDevicesDao.getAll();
      expect(devices.single.id, equals('phone-1'));
      expect(devices.single.platform, equals('ios'));
    });

    test('upgrading to v7 rewrites removed agent identities to password', () async {
      final rawDb = sqlite3.open(tempDbFile.path);
      rawDb.execute(_hostsTableAtV2);
      rawDb.execute('''
        CREATE TABLE IF NOT EXISTS "workspaces" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "name" TEXT NOT NULL,
          "color_code" TEXT NULL,
          "created_at" INTEGER NOT NULL
        );
      ''');
      rawDb.execute('''
        CREATE TABLE IF NOT EXISTS "identities" (
          "id" TEXT NOT NULL PRIMARY KEY,
          "workspace_id" TEXT NOT NULL REFERENCES workspaces (id) ON DELETE CASCADE,
          "title" TEXT NOT NULL,
          "username" TEXT NOT NULL,
          "auth_type" TEXT NOT NULL,
          "password_encrypted" TEXT NULL,
          "private_key_encrypted" TEXT NULL,
          "passphrase_encrypted" TEXT NULL,
          "created_at" INTEGER NOT NULL
        );
      ''');
      rawDb.execute('PRAGMA user_version = 6;');
      rawDb.execute(
        "INSERT INTO workspaces (id, name, created_at) "
        "VALUES ('ws-1', 'Default Workspace', 1600000000);",
      );
      rawDb.execute(
        'INSERT INTO identities (id, workspace_id, title, username, auth_type, created_at) '
        "VALUES ('id-agent', 'ws-1', 'Agent Identity', 'root', 'agent', 1600000000);",
      );
      // Supported auth types must survive the rewrite untouched.
      rawDb.execute(
        'INSERT INTO identities (id, workspace_id, title, username, auth_type, private_key_encrypted, created_at) '
        "VALUES ('id-key', 'ws-1', 'Key Identity', 'deploy', 'key', 'cipher', 1600000000);",
      );
      rawDb.close();

      final appDb = AppDatabase(NativeDatabase(tempDbFile));
      db = appDb;

      final rows = await appDb.select(appDb.identities).get();
      final migrated = rows.firstWhere((row) => row.id == 'id-agent');
      expect(migrated.authType, equals('password'));
      expect(migrated.title, equals('Agent Identity'));
      expect(migrated.username, equals('root'));

      final untouched = rows.firstWhere((row) => row.id == 'id-key');
      expect(untouched.authType, equals('key'));
      expect(untouched.privateKeyEncrypted, equals('cipher'));
    });
  });
}
