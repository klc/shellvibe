import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

class _DelayedEncryptionEngine extends EncryptionEngine {
  final EncryptionEngine delegate;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  _DelayedEncryptionEngine(this.delegate);

  @override
  Future<SecretKey> deriveMasterKeyInBackground({
    required String masterPassword,
    required Uint8List salt,
  }) async {
    started.complete();
    await release.future;
    return delegate.deriveMasterKeyInBackground(
      masterPassword: masterPassword,
      salt: salt,
    );
  }

  @override
  Future<String> decrypt({
    required String encryptedBase64,
    required SecretKey secretKey,
  }) {
    return delegate.decrypt(
      encryptedBase64: encryptedBase64,
      secretKey: secretKey,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Argon2id with production parameters is far too slow for a unit test.
  final engine = EncryptionEngine(
    kdf: Argon2id(parallelism: 1, memory: 8, iterations: 1, hashLength: 32),
  );

  VaultKeyService buildService() => VaultKeyService(
    encryptionEngine: engine,
    secureStorageService: SecureStorageService(),
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('VaultKeyService', () {
    test('creates one DEK and reuses it across calls', () async {
      final service = buildService();

      final first = await (await service.getDek()).extractBytes();
      final second = await (await service.getDek()).extractBytes();

      expect(first.length, equals(32));
      expect(second, equals(first));
    });

    test('setting a master password preserves the existing DEK', () async {
      final service = buildService();
      final before = await (await service.getDek()).extractBytes();

      await service.configureMasterPassword('correct horse battery');

      final after = await (await service.getDek()).extractBytes();
      expect(after, equals(before));
    });

    test(
      'protecting the vault removes the plaintext key from the keychain',
      () async {
        final storage = SecureStorageService();
        final service = VaultKeyService(
          encryptionEngine: engine,
          secureStorageService: storage,
        );

        await service.getDek();
        expect(await storage.getMasterKey(), isNotNull);

        await service.configureMasterPassword('correct horse battery');

        expect(await storage.getMasterKey(), isNull);
        expect(
          await storage.read(key: SecureStorageKeys.wrappedDek),
          isNotNull,
        );
      },
    );

    test(
      'locking blocks key access until the right password unwraps it',
      () async {
        final service = buildService();
        final original = await (await service.getDek()).extractBytes();

        await service.configureMasterPassword('correct horse battery');
        service.lock();

        expect(() => service.getDek(), throwsA(isA<VaultLockedException>()));
        expect(await service.unlock('wrong password'), isFalse);
        expect(() => service.getDek(), throwsA(isA<VaultLockedException>()));

        expect(await service.unlock('correct horse battery'), isTrue);
        expect(await (await service.getDek()).extractBytes(), equals(original));
      },
    );

    test(
      'does not restore the DEK when lock races with password unwrap',
      () async {
        final storage = SecureStorageService();
        final configured = VaultKeyService(
          encryptionEngine: engine,
          secureStorageService: storage,
        );
        await configured.getDek();
        await configured.configureMasterPassword('correct horse battery');

        final delayedEngine = _DelayedEncryptionEngine(engine);
        final service = VaultKeyService(
          encryptionEngine: delayedEngine,
          secureStorageService: storage,
        );
        final unlockFuture = service.unlock('correct horse battery');
        await delayedEngine.started.future;

        service.lock();
        delayedEngine.release.complete();

        expect(await unlockFuture, isFalse);
        expect(service.isUnlockedInMemory, isFalse);
      },
    );

    test(
      'a fresh instance starts locked when a master password is configured',
      () async {
        await buildService().configureMasterPassword('correct horse battery');

        // Simulates an app restart: same keychain, new in-memory state.
        final restarted = buildService();
        expect(await restarted.isMasterPasswordConfigured(), isTrue);
        expect(restarted.isUnlockedInMemory, isFalse);
        expect(() => restarted.getDek(), throwsA(isA<VaultLockedException>()));
      },
    );

    test('removing the master password restores unattended access', () async {
      final service = buildService();
      final original = await (await service.getDek()).extractBytes();

      await service.configureMasterPassword('correct horse battery');
      await service.removeMasterPassword();

      expect(await service.isMasterPasswordConfigured(), isFalse);
      final reopened = buildService();
      expect(await (await reopened.getDek()).extractBytes(), equals(original));
    });
  });
}
