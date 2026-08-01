import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/core/crypto/encryption_engine.dart';
import 'package:terly2/core/sync/e2ee_cloud_sync_service.dart';
import 'package:terly2/features/vault/data/vault_key_service.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/storage/secure_storage_service.dart';

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
  late E2EECloudSyncService syncService;
  final engine = EncryptionEngine();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db1 = AppDatabase(NativeDatabase.memory());
    db2 = AppDatabase(NativeDatabase.memory());
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
  });

  group('E2EECloudSyncService Unit Tests', () {
    test('exportEncryptedBackup generates valid Zero-Knowledge payload', () async {
      const password = 'SuperSecretMasterPassword123!';
      final backupJson = await syncService.exportEncryptedBackup(
        db: db1,
        masterPassword: password,
      );

      expect(backupJson, contains('schema_version'));
      expect(backupJson, contains('salt'));
      expect(backupJson, contains('payload'));
      // The wrapped vault key is what makes the backup restorable elsewhere.
      expect(backupJson, contains('dek_wrapped'));
    });

    test('identity secrets survive a restore onto a different device', () async {
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
      await db1.into(db1.identities).insert(
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

      final restored = await (db2.select(db2.identities)
            ..where((t) => t.id.equals('ident_sync')))
          .getSingle();
      final decrypted = await engine.decrypt(
        encryptedBase64: restored.passwordEncrypted!,
        secretKey: await device2KeyService.getDek(),
      );
      expect(decrypted, equals('hunter2'));
    });

    test('importEncryptedBackup restores database state into db2', () async {
      const password = 'SuperSecretMasterPassword123!';

      // 1. Export from db1
      final backupJson = await syncService.exportEncryptedBackup(
        db: db1,
        masterPassword: password,
      );

      // 2. Verify db2 is empty initially
      final db2WorkspacesBefore = await db2.workspacesDao.getAllWorkspaces();
      expect(db2WorkspacesBefore, isEmpty);

      // 3. Import backup into db2
      await syncService.importEncryptedBackup(
        backupPackageJson: backupJson,
        db: db2,
        masterPassword: password,
      );

      // 4. Verify data was imported
      final db2Workspaces = await db2.workspacesDao.getAllWorkspaces();
      expect(db2Workspaces.length, equals(1));
      expect(db2Workspaces.first.name, equals('Production Workspace'));

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

    test('importEncryptedBackup fails with wrong password', () async {
      const password = 'CorrectPassword123';
      const wrongPassword = 'WrongPassword456';

      final backupJson = await syncService.exportEncryptedBackup(
        db: db1,
        masterPassword: password,
      );

      expect(
        () async => await syncService.importEncryptedBackup(
          backupPackageJson: backupJson,
          db: db2,
          masterPassword: wrongPassword,
        ),
        throwsA(isA<CryptoException>()),
      );
    });
  });
}

