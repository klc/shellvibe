import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

class _FailingWrappedDekDelete extends SecureStorageService {
  @override
  Future<void> delete({required String key}) {
    if (key == SecureStorageKeys.wrappedDek) throw StateError('keychain');
    return super.delete(key: key);
  }
}

/// A keychain that stores the wrapped key garbled, as a failing write might.
class _GarblingWrappedDekWrite extends SecureStorageService {
  @override
  Future<void> write({required String key, required String value}) =>
      super.write(
        key: key,
        value: key == SecureStorageKeys.wrappedDek
            ? base64.encode(List.filled(60, 1))
            : value,
      );
}

class _DelayedEncryptionEngine extends EncryptionEngine {
  final EncryptionEngine delegate;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  _DelayedEncryptionEngine(this.delegate);

  @override
  Future<SecretKey> deriveMasterKeyInBackground({
    required String masterPassword,
    required Uint8List salt,
    Argon2Params? params,
  }) async {
    started.complete();
    await release.future;
    return delegate.deriveMasterKeyInBackground(
      masterPassword: masterPassword,
      salt: salt,
      params: params,
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

    test('callers that race on an empty keychain share one DEK', () async {
      // Sync applying an identity while the user saves another: both read an
      // empty keychain, and a second generated key would overwrite the first.
      final service = buildService();

      final keys = await Future.wait([
        service.getDek(),
        service.getDek(),
        service.getDek(),
      ]);
      final bytes = [for (final key in keys) await key.extractBytes()];
      final stored = await SecureStorageService().getMasterKey();

      expect(bytes[1], equals(bytes[0]));
      expect(bytes[2], equals(bytes[0]));
      expect(stored, equals(bytes[0]));
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

    test('a failure while removing the password leaves plain mode', () async {
      final setup = buildService();
      final original = await (await setup.getDek()).extractBytes();
      await setup.configureMasterPassword('correct horse battery');
      final service = VaultKeyService(
        encryptionEngine: engine,
        secureStorageService: _FailingWrappedDekDelete(),
      );
      expect(await service.unlock('correct horse battery'), isTrue);

      await expectLater(service.removeMasterPassword(), throwsStateError);

      expect(await service.isMasterPasswordConfigured(), isFalse);
      final reopened = buildService();
      expect(await (await reopened.getDek()).extractBytes(), equals(original));
    });
  });

  group('a lost key', () {
    test('is not replaced while encrypted rows remain', () async {
      // The keychain came back empty (an Android keystore reset, a transfer
      // that carried the database only), the database did not.
      final storage = SecureStorageService();
      final service = VaultKeyService(
        encryptionEngine: engine,
        secureStorageService: storage,
        hasEncryptedData: () async => true,
      );

      expect(await service.isKeyLost(), isTrue);
      await expectLater(
        service.getDek(),
        throwsA(isA<VaultKeyLostException>()),
      );
      expect(await storage.getMasterKey(), isNull);
    });

    test('is not replaced while a wrapped copy remains', () async {
      await buildService().configureMasterPassword('correct horse battery');
      // Only the salt went: the vault now reads as unprotected.
      await SecureStorageService().deleteMasterSalt();

      final service = buildService();
      expect(await service.isKeyLost(), isTrue);
      await expectLater(
        service.getDek(),
        throwsA(isA<VaultKeyLostException>()),
      );
    });

    test('is reported when the wrapped key is gone', () async {
      await buildService().configureMasterPassword('correct horse battery');
      await SecureStorageService().delete(key: SecureStorageKeys.wrappedDek);

      expect(await buildService().isKeyLost(), isTrue);
    });

    test('a first run is not a lost key', () async {
      final service = VaultKeyService(
        encryptionEngine: engine,
        secureStorageService: SecureStorageService(),
        hasEncryptedData: () async => false,
      );
      expect(await service.isKeyLost(), isFalse);
      expect(await service.getDek(), isNotNull);
      expect(await service.isKeyLost(), isFalse);
    });

    test('a reset starts over under a new key', () async {
      final service = buildService();
      final original = await (await service.getDek()).extractBytes();
      await service.configureMasterPassword('correct horse battery');

      await service.reset();

      expect(await service.isMasterPasswordConfigured(), isFalse);
      expect(await service.isKeyLost(), isFalse);
      final fresh = await (await service.getDek()).extractBytes();
      expect(fresh, isNot(equals(original)));
      expect(
        await SecureStorageService().read(key: SecureStorageKeys.wrappedDek),
        isNull,
      );
    });
  });

  group('setting a master password', () {
    test(
      'keeps the plaintext key when the stored record does not open',
      () async {
        final storage = _GarblingWrappedDekWrite();
        final service = VaultKeyService(
          encryptionEngine: engine,
          secureStorageService: storage,
        );
        final original = await (await service.getDek()).extractBytes();

        await expectLater(
          service.configureMasterPassword('correct horse battery'),
          throwsStateError,
        );

        expect(await service.isMasterPasswordConfigured(), isFalse);
        expect(await storage.getMasterKey(), equals(original));
        expect(await buildService().isKeyLost(), isFalse);
      },
    );

    test('an unlock clears a plaintext key a setup left behind', () async {
      final storage = SecureStorageService();
      final service = buildService();
      final original = await (await service.getDek()).extractBytes();
      await service.configureMasterPassword('correct horse battery');
      // As if setup had stopped before deleting it.
      await storage.saveMasterKey(original);

      final restarted = buildService();
      expect(await restarted.unlock('correct horse battery'), isTrue);

      expect(await storage.getMasterKey(), isNull);
      expect(await (await restarted.getDek()).extractBytes(), equals(original));
    });

    test('unlocks under the KDF cost it was set with', () async {
      await buildService().configureMasterPassword('correct horse battery');

      // A later build raised the default cost.
      final costlier = VaultKeyService(
        encryptionEngine: EncryptionEngine(
          kdf: Argon2id(
            parallelism: 1,
            memory: 16,
            iterations: 2,
            hashLength: 32,
          ),
        ),
        secureStorageService: SecureStorageService(),
      );
      expect(await costlier.unlock('correct horse battery'), isTrue);
    });
  });
}
