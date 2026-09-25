import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/features/vault/data/repositories/vault_env_repository.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// A key service that never actually resolves a key. Used to prove that
/// [VaultEnvRepository.resolveForShell] never touches the vault key when a
/// workspace has no rows — a real `getDek()` reads secure storage, which in a
/// protected-but-locked vault would throw and in some test hosts never
/// completes at all, so any call at all here is the bug this guards against.
class _RecordingKeyService implements VaultKeyService {
  int getDekCalls = 0;

  @override
  Future<SecretKey> getDek() async {
    getDekCalls++;
    throw StateError('getDek should not have been called');
  }

  @override
  Future<bool> isMasterPasswordConfigured() async => false;

  @override
  bool get isUnlockedInMemory => false;

  @override
  Future<void> configureMasterPassword(String masterPassword) =>
      throw UnimplementedError();

  @override
  Future<bool> unlock(String masterPassword) => throw UnimplementedError();

  @override
  void lock() => throw UnimplementedError();

  @override
  Future<void> removeMasterPassword() => throw UnimplementedError();

  @override
  EncryptionEngine get encryptionEngine => throw UnimplementedError();

  @override
  SecureStorageService get secureStorageService => throw UnimplementedError();
}

/// A key service that always reports the vault as locked, for the
/// `resolveForShell` "locked" branch.
class _LockedKeyService implements VaultKeyService {
  @override
  Future<SecretKey> getDek() async => throw const VaultLockedException();

  @override
  Future<bool> isMasterPasswordConfigured() async => true;

  @override
  bool get isUnlockedInMemory => false;

  @override
  Future<void> configureMasterPassword(String masterPassword) =>
      throw UnimplementedError();

  @override
  Future<bool> unlock(String masterPassword) => throw UnimplementedError();

  @override
  void lock() => throw UnimplementedError();

  @override
  Future<void> removeMasterPassword() => throw UnimplementedError();

  @override
  EncryptionEngine get encryptionEngine => throw UnimplementedError();

  @override
  SecureStorageService get secureStorageService => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late EncryptionEngine engine;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'default',
        name: 'Default Workspace',
        createdAt: DateTime.now(),
      ),
    );
    engine = EncryptionEngine();
  });

  tearDown(() async {
    await db.close();
  });

  VaultEnvRepository buildRepo({VaultKeyService? keyService}) {
    return VaultEnvRepository(
      dao: db.vaultEnvVarsDao,
      encryptionEngine: engine,
      vaultKeyService:
          keyService ??
          VaultKeyService(
            encryptionEngine: engine,
            secureStorageService: SecureStorageService(),
          ),
    );
  }

  group('save', () {
    test(
      'encrypts the value: the stored row never carries plaintext',
      () async {
        final repo = buildRepo();

        await repo.save(
          workspaceId: 'default',
          name: 'API_TOKEN',
          value: 'super-secret-token',
        );

        final rows = await db.vaultEnvVarsDao.getByWorkspace('default');
        expect(rows.single.valueEncrypted, isNot(equals('super-secret-token')));
      },
    );

    test('a saved value round-trips through decryptValue', () async {
      final repo = buildRepo();

      final saved = await repo.save(
        workspaceId: 'default',
        name: 'API_TOKEN',
        value: 'super-secret-token',
      );

      final decrypted = await repo.decryptValue(saved.id);
      expect(decrypted, equals('super-secret-token'));
    });

    test('rejects a name with an invalid shape', () async {
      final repo = buildRepo();

      await expectLater(
        repo.save(workspaceId: 'default', name: '1INVALID', value: 'x'),
        throwsA(isA<VaultEnvNameException>()),
      );
    });

    test('rejects a reserved name', () async {
      final repo = buildRepo();

      await expectLater(
        repo.save(workspaceId: 'default', name: 'TERM', value: 'x'),
        throwsA(isA<VaultEnvNameException>()),
      );
    });

    test('rejects a duplicate name within the same workspace', () async {
      final repo = buildRepo();
      await repo.save(workspaceId: 'default', name: 'DUP', value: 'first');

      await expectLater(
        repo.save(workspaceId: 'default', name: 'DUP', value: 'second'),
        throwsA(isA<VaultEnvNameException>()),
      );
    });

    test(
      'editing a row in place is not treated as a duplicate of itself',
      () async {
        final repo = buildRepo();
        final saved = await repo.save(
          workspaceId: 'default',
          name: 'KEEP_NAME',
          value: 'first',
        );

        // Re-saving under its own id with the same name must not throw.
        await repo.save(
          id: saved.id,
          workspaceId: 'default',
          name: 'KEEP_NAME',
          value: 'second',
        );

        final decrypted = await repo.decryptValue(saved.id);
        expect(decrypted, equals('second'));
      },
    );
  });

  group('resolveForShell', () {
    test('a workspace with no rows never calls getDek', () async {
      final keyService = _RecordingKeyService();
      final repo = buildRepo(keyService: keyService);

      final result = await repo.resolveForShell(workspaceId: 'default');

      expect(result.vars, isEmpty);
      expect(result.vaultLocked, isFalse);
      expect(result.undecryptable, 0);
      expect(keyService.getDekCalls, 0);
    });

    test('a locked vault reports vaultLocked and no vars', () async {
      final repo = buildRepo();
      await repo.save(workspaceId: 'default', name: 'API_TOKEN', value: 'x');

      final lockedRepo = buildRepo(keyService: _LockedKeyService());
      final result = await lockedRepo.resolveForShell(workspaceId: 'default');

      expect(result.vaultLocked, isTrue);
      expect(result.vars, isEmpty);
      expect(result.undecryptable, 0);
    });

    test('resolves decrypted vars for a workspace with rows', () async {
      final repo = buildRepo();
      await repo.save(workspaceId: 'default', name: 'API_TOKEN', value: 'tok');
      await repo.save(
        workspaceId: 'default',
        name: 'OTHER_VAR',
        value: 'other',
      );

      final result = await repo.resolveForShell(workspaceId: 'default');

      expect(result.vaultLocked, isFalse);
      expect(result.undecryptable, 0);
      expect(result.vars, equals({'API_TOKEN': 'tok', 'OTHER_VAR': 'other'}));
    });

    test('a row that cannot be decrypted is skipped and counted', () async {
      // Written directly with ciphertext this install's key cannot open —
      // what a restored backup or a lost keychain entry leaves behind.
      await db.vaultEnvVarsDao.insert(
        VaultEnvVarsCompanion.insert(
          id: 'broken',
          workspaceId: 'default',
          name: 'BROKEN_VAR',
          valueEncrypted: 'not-decryptable-with-this-key',
          createdAt: DateTime.now(),
        ),
      );
      final repo = buildRepo();

      final result = await repo.resolveForShell(workspaceId: 'default');

      expect(result.vaultLocked, isFalse);
      expect(result.vars, isEmpty);
      expect(result.undecryptable, 1);
    });

    group('rows that arrived by sync, unvalidated', () {
      late VaultKeyService keyService;

      setUp(() {
        keyService = VaultKeyService(
          encryptionEngine: engine,
          secureStorageService: SecureStorageService(),
        );
      });

      Future<void> insertSynced(
        String id,
        String name,
        String value,
        DateTime createdAt,
      ) async {
        await db.vaultEnvVarsDao.insert(
          VaultEnvVarsCompanion.insert(
            id: id,
            workspaceId: 'default',
            name: name,
            valueEncrypted: await engine.encrypt(
              plaintext: value,
              secretKey: await keyService.getDek(),
            ),
            createdAt: createdAt,
          ),
        );
      }

      test(
        'a name two devices both added resolves to the newest row',
        () async {
          // Inserted newest first, so the result cannot be insertion order.
          await insertSynced('b', 'SHARED', 'newer', DateTime(2026, 9, 2));
          await insertSynced('a', 'SHARED', 'older', DateTime(2026, 9, 1));

          final result = await buildRepo(
            keyService: keyService,
          ).resolveForShell(workspaceId: 'default');

          expect(result.vars, equals({'SHARED': 'newer'}));
        },
      );

      test('a malformed or reserved name is not handed to the shell', () async {
        final now = DateTime.now();
        await insertSynced('bad', 'NOT=VALID', 'x', now);
        await insertSynced('reserved', 'TERM_THEME', 'x', now);
        await insertSynced('ok', 'GOOD', 'y', now);

        final result = await buildRepo(
          keyService: keyService,
        ).resolveForShell(workspaceId: 'default');

        expect(result.vars, equals({'GOOD': 'y'}));
        expect(result.undecryptable, 0);
      });
    });
  });
}
