import 'dart:io';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/core/sync/e2ee_cloud_sync_service.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

import '../../../support/fast_crypto.dart';

E2EECloudSyncService _buildService(EncryptionEngine engine) {
  return E2EECloudSyncService(
    cryptoEngine: engine,
    vaultKeyService: VaultKeyService(
      encryptionEngine: engine,
      secureStorageService: SecureStorageService(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db1;
  late AppDatabase db2;
  late Directory databaseDirectory;
  late E2EECloudSyncService syncService;
  final engine = fastEncryptionEngine();
  late bool previousMultipleDatabaseWarningSetting;

  setUpAll(() {
    previousMultipleDatabaseWarningSetting =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    // db1 and db2 intentionally represent separate devices and use separate
    // temporary SQLite files. Drift's debug warning cannot distinguish this
    // valid fixture from accidentally sharing an executor.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        previousMultipleDatabaseWarningSetting;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    databaseDirectory = await Directory.systemTemp.createTemp(
      'shellvibe-e2ee-test-',
    );
    db1 = AppDatabase(
      NativeDatabase(File('${databaseDirectory.path}/device-1.sqlite')),
    );
    db2 = AppDatabase(
      NativeDatabase(File('${databaseDirectory.path}/device-2.sqlite')),
    );
    syncService = _buildService(engine);

    // Populate db1 with test data
    await db1.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'ws_test',
        name: 'Production Workspace',
        createdAt: DateTime.now(),
      ),
    );

    await db1.hostsDao.insertHost(
      HostsCompanion.insert(
        id: 'host_sync',
        workspaceId: 'ws_test',
        label: 'Sync Host',
        hostname: 'sync.local',
        createdAt: DateTime.now(),
      ),
    );

    await db1.tunnelsDao.insertRule(
      PortForwardRulesCompanion.insert(
        id: 'rule_sync',
        hostId: 'host_sync',
        type: 'local',
        localPort: 8080,
        remoteHost: const Value('127.0.0.1'),
        remotePort: const Value(80),
        autoStart: const Value(true),
      ),
    );

    await db1.snippetsDao.insertSnippet(
      SnippetsCompanion.insert(
        id: 'snip_sync',
        workspaceId: 'ws_test',
        title: 'Sync Test Snippet',
        code: 'echo "Sync OK"',
      ),
    );

    await db1.runbooksDao.insertRunbook(
      RunbooksCompanion.insert(
        id: 'rb_sync',
        workspaceId: 'ws_test',
        title: 'Sync Test Runbook',
        createdAt: DateTime.now(),
      ),
    );
  });

  tearDown(() async {
    await db1.close();
    await db2.close();
    await databaseDirectory.delete(recursive: true);
  });

  group('E2EECloudSyncService Unit Tests', () {
    test(
      'identity secrets survive a restore onto a different device',
      () async {
        const password = 'SuperSecretMasterPassword123!';

        // Encrypt a secret with device 1's vault key.
        final device1Dek = await VaultKeyService(
          encryptionEngine: engine,
          secureStorageService: SecureStorageService(),
        ).getDek();
        final storedSecret = await engine.encrypt(
          plaintext: 'hunter2',
          secretKey: device1Dek,
        );
        await db1
            .into(db1.identities)
            .insert(
              IdentitiesCompanion.insert(
                id: 'ident_sync',
                workspaceId: 'ws_test',
                title: 'Prod root',
                username: 'root',
                authType: 'password',
                passwordEncrypted: Value(storedSecret),
                createdAt: DateTime.now(),
              ),
            );

        final backupJson = await syncService.exportEncryptedBackup(
          db: db1,
          masterPassword: password,
        );

        // Simulate a fresh device: empty keychain, hence a different vault key.
        FlutterSecureStorage.setMockInitialValues({});
        final device2KeyService = VaultKeyService(
          encryptionEngine: engine,
          secureStorageService: SecureStorageService(),
        );
        final device2Service = E2EECloudSyncService(
          cryptoEngine: engine,
          vaultKeyService: device2KeyService,
        );

        final result = await device2Service.importEncryptedBackup(
          backupPackageJson: backupJson,
          db: db2,
          masterPassword: password,
        );

        expect(result.secretsRecovered, isTrue);

        final restored = await (db2.select(
          db2.identities,
        )..where((t) => t.id.equals('ident_sync'))).getSingle();
        final decrypted = await engine.decrypt(
          encryptedBase64: restored.passwordEncrypted!,
          secretKey: await device2KeyService.getDek(),
        );
        expect(decrypted, equals('hunter2'));
      },
    );

    test('a vault environment variable survives a restore onto a different '
        'device', () async {
      const password = 'SuperSecretMasterPassword123!';

      // Encrypt a value with device 1's vault key, same as an identity
      // secret would be.
      final device1Dek = await VaultKeyService(
        encryptionEngine: engine,
        secureStorageService: SecureStorageService(),
      ).getDek();
      final storedValue = await engine.encrypt(
        plaintext: 'ghp_supersecrettoken',
        secretKey: device1Dek,
      );
      await db1
          .into(db1.vaultEnvVars)
          .insert(
            VaultEnvVarsCompanion.insert(
              id: 'env_sync',
              workspaceId: 'ws_test',
              name: 'GITHUB_TOKEN',
              valueEncrypted: storedValue,
              createdAt: DateTime.now(),
            ),
          );

      final backupJson = await syncService.exportEncryptedBackup(
        db: db1,
        masterPassword: password,
      );

      // Simulate a fresh device: empty keychain, hence a different vault key.
      FlutterSecureStorage.setMockInitialValues({});
      final device2KeyService = VaultKeyService(
        encryptionEngine: engine,
        secureStorageService: SecureStorageService(),
      );
      final device2Service = E2EECloudSyncService(
        cryptoEngine: engine,
        vaultKeyService: device2KeyService,
      );

      final result = await device2Service.importEncryptedBackup(
        backupPackageJson: backupJson,
        db: db2,
        masterPassword: password,
      );

      expect(result.secretsRecovered, isTrue);

      final restored = await (db2.select(
        db2.vaultEnvVars,
      )..where((t) => t.id.equals('env_sync'))).getSingle();
      expect(restored.name, equals('GITHUB_TOKEN'));
      expect(restored.workspaceId, equals('ws_test'));

      final decrypted = await engine.decrypt(
        encryptedBase64: restored.valueEncrypted,
        secretKey: await device2KeyService.getDek(),
      );
      expect(decrypted, equals('ghp_supersecrettoken'));
    });

    test(
      'a secret the backup key cannot open does not stop the restore',
      () async {
        const password = 'SuperSecretMasterPassword123!';

        // Under a key this device does not hold: what keychain loss or another
        // device's sync operation leaves behind. Export carries it as it is.
        final foreignKey = SecretKey(engine.generateKey());
        final foreignPassword = await engine.encrypt(
          plaintext: 'hunter2',
          secretKey: foreignKey,
        );
        final foreignValue = await engine.encrypt(
          plaintext: 'ghp_unreadable',
          secretKey: foreignKey,
        );
        await db1
            .into(db1.identities)
            .insert(
              IdentitiesCompanion.insert(
                id: 'ident_foreign',
                workspaceId: 'ws_test',
                title: 'Legacy root',
                username: 'root',
                authType: 'password',
                passwordEncrypted: Value(foreignPassword),
                createdAt: DateTime.now(),
              ),
            );
        await db1
            .into(db1.vaultEnvVars)
            .insert(
              VaultEnvVarsCompanion.insert(
                id: 'env_foreign',
                workspaceId: 'ws_test',
                name: 'LEGACY_TOKEN',
                valueEncrypted: foreignValue,
                createdAt: DateTime.now(),
              ),
            );

        final backupJson = await syncService.exportEncryptedBackup(
          db: db1,
          masterPassword: password,
        );

        // Before the fix this threw CryptoException and restored nothing.
        await syncService.importEncryptedBackup(
          backupPackageJson: backupJson,
          db: db2,
          masterPassword: password,
        );

        final hosts = await db2.select(db2.hosts).get();
        expect(hosts.map((h) => h.id), contains('host_sync'));

        final identity = await (db2.select(
          db2.identities,
        )..where((t) => t.id.equals('ident_foreign'))).getSingle();
        expect(identity.passwordEncrypted, equals(foreignPassword));

        final envVar = await (db2.select(
          db2.vaultEnvVars,
        )..where((t) => t.id.equals('env_foreign'))).getSingle();
        expect(envVar.valueEncrypted, equals(foreignValue));
      },
    );

    test('a vault environment variable is dropped from a backup that excludes '
        'identities', () async {
      const password = 'SuperSecretMasterPassword123!';

      await db1
          .into(db1.vaultEnvVars)
          .insert(
            VaultEnvVarsCompanion.insert(
              id: 'env_excluded',
              workspaceId: 'ws_test',
              name: 'EXCLUDED_VAR',
              valueEncrypted: 'ciphertext',
              createdAt: DateTime.now(),
            ),
          );

      final backupJson = await syncService.exportEncryptedBackup(
        db: db1,
        masterPassword: password,
        scope: BackupScope.of(const [BackupCategory.hosts]),
      );

      final opened = await BackupEnvelope(
        crypto: fastEncryptionEngine(),
      ).open(envelopeJson: backupJson, secret: password);
      expect(opened.payloadJson, isNot(contains('vault_env_vars')));
    });

    test('importEncryptedBackup restores database state into db2', () async {
      const password = 'SuperSecretMasterPassword123!';

      // 1. Export from db1
      final backupJson = await syncService.exportEncryptedBackup(
        db: db1,
        masterPassword: password,
      );

      // 2. A fresh database is seeded with the protected default workspace.
      final db2WorkspacesBefore = await db2.workspacesDao.getAllWorkspaces();
      expect(db2WorkspacesBefore.map((workspace) => workspace.id), ['default']);

      // 3. Import backup into db2
      await syncService.importEncryptedBackup(
        backupPackageJson: backupJson,
        db: db2,
        masterPassword: password,
      );

      // 4. Verify data was imported
      final db2Workspaces = await db2.workspacesDao.getAllWorkspaces();
      expect(
        db2Workspaces.map((workspace) => workspace.id),
        containsAll(['default', 'ws_test']),
      );
      expect(
        db2Workspaces
            .singleWhere((workspace) => workspace.id == 'ws_test')
            .name,
        equals('Production Workspace'),
      );

      final db2Rules = await db2.tunnelsDao.getRulesForHost('host_sync');
      expect(db2Rules.length, equals(1));
      expect(db2Rules.first.id, equals('rule_sync'));
      expect(db2Rules.first.localPort, equals(8080));
      expect(db2Rules.first.remoteHost, equals('127.0.0.1'));
      expect(db2Rules.first.remotePort, equals(80));
      expect(db2Rules.first.autoStart, equals(true));

      final db2Snippets = await db2.snippetsDao.getAllSnippets();
      expect(db2Snippets.length, equals(1));
      expect(db2Snippets.first.title, equals('Sync Test Snippet'));
    });

    test('a restored host without a startup snippet drops the local one', () async {
      const password = 'SuperSecretMasterPassword123!';

      // db2 already knows the host, with a startup snippet the backup lacks.
      await db2.workspacesDao.insertWorkspace(
        WorkspacesCompanion.insert(
          id: 'ws_test',
          name: 'Production Workspace',
          createdAt: DateTime.now(),
        ),
      );
      await db2.snippetsDao.insertSnippet(
        SnippetsCompanion.insert(
          id: 'snip_sync',
          workspaceId: 'ws_test',
          title: 'Sync Test Snippet',
          code: 'echo "Sync OK"',
        ),
      );
      await db2.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'host_sync',
          workspaceId: 'ws_test',
          label: 'Sync Host',
          hostname: 'sync.local',
          startupSnippetId: const Value('snip_sync'),
          createdAt: DateTime.now(),
        ),
      );

      final backupJson = await syncService.exportEncryptedBackup(
        db: db1,
        masterPassword: password,
      );
      await syncService.importEncryptedBackup(
        backupPackageJson: backupJson,
        db: db2,
        masterPassword: password,
      );

      final host = await (db2.select(
        db2.hosts,
      )..where((h) => h.id.equals('host_sync'))).getSingle();
      expect(host.startupSnippetId, equals(null));
    });
  });
}
