import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/core/sync/e2ee_cloud_sync_service.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// A backup can now be narrowed to a set of categories.
///
/// Two things have to hold for that to be safe. A narrowed backup must not
/// delete what it left out when it is restored, and it must not carry a
/// reference to a row that was left out -- foreign keys are deferred to
/// COMMIT during a restore, so one dangling reference fails the whole thing.
/// That is the same failure a jump host produced on a phone on 2026-09-18.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase source;
  late AppDatabase target;
  late E2EECloudSyncService sync;

  const passphrase = 'scope test passphrase';

  Future<Map<String, dynamic>> payloadOf(String envelope) async {
    final opened = await BackupEnvelope().open(
      envelopeJson: envelope,
      secret: passphrase,
    );
    return jsonDecode(opened.payloadJson) as Map<String, dynamic>;
  }

  Future<void> seedSource() async {
    await source.into(source.identities).insert(
          IdentitiesCompanion.insert(
            id: 'i1',
            workspaceId: 'default',
            title: 'deploy key',
            username: 'deploy',
            authType: 'key',
            createdAt: DateTime.now(),
          ),
        );
    await source.into(source.hosts).insert(
          HostsCompanion.insert(
            id: 'h1',
            workspaceId: 'default',
            identityId: const Value('i1'),
            label: 'web',
            hostname: 'web.example.com',
            createdAt: DateTime.now(),
          ),
        );
    await source.into(source.portForwardRules).insert(
          PortForwardRulesCompanion.insert(
            id: 'p1',
            hostId: 'h1',
            type: 'local',
            localPort: 8080,
          ),
        );
    await source.into(source.templates).insert(
          TemplatesCompanion.insert(
            id: 't1',
            workspaceId: 'default',
            name: 'two panes',
            createdAt: DateTime.now(),
          ),
        );
    await source.into(source.templatePanes).insert(
          TemplatePanesCompanion.insert(
            id: 'tp1',
            templateId: 't1',
            paneOrder: 0,
            sessionType: 'ssh',
            hostId: const Value('h1'),
          ),
        );
    await source.into(source.bookmarks).insert(
          BookmarksCompanion.insert(
            id: 'b1',
            workspaceId: 'default',
            hostId: const Value('h1'),
            createdAt: DateTime.now(),
          ),
        );
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    source = AppDatabase(NativeDatabase.memory());
    target = AppDatabase(NativeDatabase.memory());

    final vaultKeyService = VaultKeyService(
      encryptionEngine: EncryptionEngine(),
      secureStorageService: SecureStorageService(),
    );
    await vaultKeyService.getDek();

    sync = E2EECloudSyncService(vaultKeyService: vaultKeyService);
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  group('the manifest', () {
    test('a full backup names every category and bumps the payload', () async {
      await seedSource();

      final payload = await payloadOf(
        await sync.exportEncryptedBackup(
          db: source,
          masterPassword: passphrase,
          settings: const {'themeMode': 'dark'},
        ),
      );

      expect(payload['version'], 3);
      expect(
        BackupScope.fromManifest(payload['included']),
        BackupScope.full,
      );
    });

    test('an excluded category is absent, not empty', () async {
      // The distinction the manifest exists for: an empty list means "you
      // have none", an absent key means "this was not backed up".
      await seedSource();

      final payload = await payloadOf(
        await sync.exportEncryptedBackup(
          db: source,
          masterPassword: passphrase,
          scope: BackupScope.of(const [BackupCategory.hosts]),
        ),
      );

      expect(payload.containsKey('hosts'), isTrue);
      expect(payload.containsKey('identities'), isFalse);
      expect(payload.containsKey('snippets'), isFalse);
      expect(payload.containsKey('bookmarks'), isFalse);
    });

    test('workspaces and host groups are written whatever the scope', () async {
      final payload = await payloadOf(
        await sync.exportEncryptedBackup(
          db: source,
          masterPassword: passphrase,
          scope: BackupScope.of(const [BackupCategory.snippetsAndRunbooks]),
        ),
      );

      expect(payload['workspaces'], isA<List>());
      expect(payload['host_groups'], isA<List>());
    });

    test('a payload with no manifest reads as a full backup', () {
      // Every backup taken before scopes existed. Reading one as "nothing was
      // included" would report a complete restore as an empty one.
      expect(BackupScope.fromManifest(null), BackupScope.full);
      expect(BackupScope.fromManifest('hosts'), BackupScope.full);
    });

    test('an unknown category name is ignored, not fatal', () {
      final scope = BackupScope.fromManifest(['hosts', 'time_machine']);

      expect(scope.contains(BackupCategory.hosts), isTrue);
      expect(scope.isFull, isFalse);
    });

    test('port forwards declare their dependency on hosts', () {
      final scope = BackupScope.of(const [BackupCategory.portForwards]);

      expect(scope.unmetDependencies, {BackupCategory.portForwards});
      expect(BackupScope.full.unmetDependencies, isEmpty);
    });
  });

  group('restoring a narrowed backup', () {
    test('leaves the categories it omits untouched', () async {
      // The promise that makes a partial backup safe to restore at all.
      await seedSource();

      await target.into(target.identities).insert(
            IdentitiesCompanion.insert(
              id: 'local-1',
              workspaceId: 'default',
              title: 'kept',
              username: 'root',
              authType: 'key',
              createdAt: DateTime.now(),
            ),
          );

      await sync.importEncryptedBackup(
        backupPackageJson: await sync.exportEncryptedBackup(
          db: source,
          masterPassword: passphrase,
          scope: BackupScope.of(const [BackupCategory.hosts]),
        ),
        db: target,
        masterPassword: passphrase,
      );

      final identities = await target.select(target.identities).get();
      expect(identities.map((i) => i.id), contains('local-1'));
    });

    test('a host whose identity was left out arrives without one', () async {
      await seedSource();

      final result = await sync.importEncryptedBackup(
        backupPackageJson: await sync.exportEncryptedBackup(
          db: source,
          masterPassword: passphrase,
          scope: BackupScope.of(const [BackupCategory.hosts]),
        ),
        db: target,
        masterPassword: passphrase,
      );

      final host = await (target.select(target.hosts)
            ..where((h) => h.id.equals('h1')))
          .getSingle();

      expect(host.identityId, isNull);
      expect(result.repairs.hostsWithoutIdentity, 1);
      expect(result.repairs.messages.first, contains('without credentials'));
    });

    test('the same host keeps its identity when the device already has it',
        () async {
      // The reference is repaired against the database, not against the
      // payload: a partial backup may point at a row this device already has.
      await seedSource();

      await sync.importEncryptedBackup(
        backupPackageJson: await sync.exportEncryptedBackup(
          db: source,
          masterPassword: passphrase,
          scope: BackupScope.of(const [BackupCategory.identities]),
        ),
        db: target,
        masterPassword: passphrase,
      );

      final result = await sync.importEncryptedBackup(
        backupPackageJson: await sync.exportEncryptedBackup(
          db: source,
          masterPassword: passphrase,
          scope: BackupScope.of(const [BackupCategory.hosts]),
        ),
        db: target,
        masterPassword: passphrase,
      );

      final host = await (target.select(target.hosts)
            ..where((h) => h.id.equals('h1')))
          .getSingle();

      expect(host.identityId, 'i1');
      expect(result.repairs.hostsWithoutIdentity, 0);
    });

    test('a port forward without its host is skipped, not fatal', () async {
      // `port_forward_rules.host_id` is NOT NULL. Writing it anyway would fail
      // the whole transaction at COMMIT.
      await seedSource();

      final result = await sync.importEncryptedBackup(
        backupPackageJson: await sync.exportEncryptedBackup(
          db: source,
          masterPassword: passphrase,
          scope: BackupScope.of(const [BackupCategory.portForwards]),
        ),
        db: target,
        masterPassword: passphrase,
      );

      expect(await target.select(target.portForwardRules).get(), isEmpty);
      expect(result.repairs.skippedPortForwards, 1);
    });

    test('a bookmark pointing at nothing is dropped', () async {
      await seedSource();

      final result = await sync.importEncryptedBackup(
        backupPackageJson: await sync.exportEncryptedBackup(
          db: source,
          masterPassword: passphrase,
          scope: BackupScope.of(const [BackupCategory.bookmarks]),
        ),
        db: target,
        masterPassword: passphrase,
      );

      expect(await target.select(target.bookmarks).get(), isEmpty);
      expect(result.repairs.skippedBookmarks, 1);
    });

    test('a bookmark keeps its host when the host came too', () async {
      await seedSource();

      final result = await sync.importEncryptedBackup(
        backupPackageJson: await sync.exportEncryptedBackup(
          db: source,
          masterPassword: passphrase,
          scope: BackupScope.of(const [
            BackupCategory.hosts,
            BackupCategory.bookmarks,
          ]),
        ),
        db: target,
        masterPassword: passphrase,
      );

      final bookmark = await target.select(target.bookmarks).getSingle();

      expect(bookmark.hostId, 'h1');
      expect(result.repairs.skippedBookmarks, 0);
    });

    test('a template survives a backup that left its hosts behind', () async {
      // `template_panes.host_id` is deliberately not a foreign key: deleting a
      // host must not rewrite a saved layout. So Templates does not depend on
      // Hosts, and the pane is kept with a host id that resolves to nothing --
      // which is the behaviour a missing host already had.
      await seedSource();

      final result = await sync.importEncryptedBackup(
        backupPackageJson: await sync.exportEncryptedBackup(
          db: source,
          masterPassword: passphrase,
          scope: BackupScope.of(const [BackupCategory.templates]),
        ),
        db: target,
        masterPassword: passphrase,
      );

      final panes = await target.select(target.templatePanes).get();

      expect(panes.single.hostId, 'h1');
      expect(result.repairs.skippedTemplatePanes, 0);
    });
  });

  group('app settings', () {
    test('round-trip through the payload', () async {
      const settings = {'themeMode': 'light', 'fontSize': 16.0};

      final result = await sync.importEncryptedBackup(
        backupPackageJson: await sync.exportEncryptedBackup(
          db: source,
          masterPassword: passphrase,
          settings: settings,
        ),
        db: target,
        masterPassword: passphrase,
      );

      expect(result.settings, settings);
    });

    test('are left out when the category is off', () async {
      final result = await sync.importEncryptedBackup(
        backupPackageJson: await sync.exportEncryptedBackup(
          db: source,
          masterPassword: passphrase,
          scope: BackupScope.of(const [BackupCategory.hosts]),
          settings: const {'themeMode': 'light'},
        ),
        db: target,
        masterPassword: passphrase,
      );

      expect(result.settings, isNull);
      expect(result.included.contains(BackupCategory.settings), isFalse);
    });
  });

  test('a full round-trip repairs nothing', () async {
    // The counters must not fire on a complete backup; a restore that reports
    // repairs it did not make is a restore nobody will trust.
    await seedSource();

    final result = await sync.importEncryptedBackup(
      backupPackageJson: await sync.exportEncryptedBackup(
        db: source,
        masterPassword: passphrase,
      ),
      db: target,
      masterPassword: passphrase,
    );

    expect(result.repairs.isEmpty, isTrue, reason: result.repairs.messages.join(' '));
    expect(result.included, BackupScope.full);
  });
}
