import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';

void main() {
  group('EncryptionEngine Unit Tests (Core Crypto)', () {
    late EncryptionEngine engine;

    setUp(() {
      engine = EncryptionEngine();
    });

    test('generateSalt generates salt of specified byte length', () {
      final salt16 = engine.generateSalt(16);
      expect(salt16.length, equals(16));

      final salt32 = engine.generateSalt(32);
      expect(salt32.length, equals(32));

      final saltAnother = engine.generateSalt(16);
      expect(salt16, isNot(equals(saltAnother)));
    });

    test('deriveMasterKey derives deterministic 256-bit key from password and salt', () async {
      const password = 'MasterPassword123!';
      final salt = engine.generateSalt(16);

      final key1 = await engine.deriveMasterKey(
        masterPassword: password,
        salt: salt,
      );
      final key2 = await engine.deriveMasterKey(
        masterPassword: password,
        salt: salt,
      );

      final bytes1 = await key1.extractBytes();
      final bytes2 = await key2.extractBytes();

      expect(bytes1.length, equals(32)); // 256-bit key
      expect(bytes1, equals(bytes2));
    });

    test('deriveMasterKey produces distinct keys for different passwords or salts', () async {
      final salt1 = engine.generateSalt(16);
      final salt2 = engine.generateSalt(16);

      final key1 = await engine.deriveMasterKey(
        masterPassword: 'PasswordA',
        salt: salt1,
      );
      final key2 = await engine.deriveMasterKey(
        masterPassword: 'PasswordB',
        salt: salt1,
      );
      final key3 = await engine.deriveMasterKey(
        masterPassword: 'PasswordA',
        salt: salt2,
      );

      final bytes1 = await key1.extractBytes();
      final bytes2 = await key2.extractBytes();
      final bytes3 = await key3.extractBytes();

      expect(bytes1, isNot(equals(bytes2)));
      expect(bytes1, isNot(equals(bytes3)));
    });

    test('deriveMasterKeyInBackground derives valid key matching synchronous derivation', () async {
      const password = 'IsolateTestPassword456!';
      final salt = engine.generateSalt(16);

      final syncKey = await engine.deriveMasterKey(
        masterPassword: password,
        salt: salt,
      );
      final bgKey = await engine.deriveMasterKeyInBackground(
        masterPassword: password,
        salt: salt,
      );

      final syncBytes = await syncKey.extractBytes();
      final bgBytes = await bgKey.extractBytes();

      expect(bgBytes.length, equals(32));
      expect(bgBytes, equals(syncBytes));
    });

    test('AES-256-GCM encryption and decryption roundtrip success', () async {
      const password = 'TestMasterPassword!';
      final salt = engine.generateSalt(16);
      final key = await engine.deriveMasterKey(
        masterPassword: password,
        salt: salt,
      );

      const plaintext = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3... secret key';
      final encryptedBase64 = await engine.encrypt(
        plaintext: plaintext,
        secretKey: key,
      );

      expect(encryptedBase64, isNotEmpty);
      expect(encryptedBase64, isNot(equals(plaintext)));

      final decrypted = await engine.decrypt(
        encryptedBase64: encryptedBase64,
        secretKey: key,
      );

      expect(decrypted, equals(plaintext));
    });

    test('decrypt throws CryptoException on tampered MAC or ciphertext', () async {
      final salt = engine.generateSalt(16);
      final key = await engine.deriveMasterKey(
        masterPassword: 'Password',
        salt: salt,
      );

      const plaintext = 'super-secret-passphrase';
      final encryptedBase64 = await engine.encrypt(
        plaintext: plaintext,
        secretKey: key,
      );

      final rawBytes = base64.decode(encryptedBase64);
      rawBytes[rawBytes.length - 1] ^= 0xFF; // Modify last byte
      final tamperedBase64 = base64.encode(rawBytes);

      expect(
        () => engine.decrypt(
          encryptedBase64: tamperedBase64,
          secretKey: key,
        ),
        throwsA(isA<CryptoException>()),
      );
    });

    test('decrypt throws CryptoException on payload length < 28 bytes', () async {
      final salt = engine.generateSalt(16);
      final key = await engine.deriveMasterKey(
        masterPassword: 'Password',
        salt: salt,
      );

      final shortBase64 = base64.encode(Uint8List(20)); // less than 28 bytes

      expect(
        () => engine.decrypt(
          encryptedBase64: shortBase64,
          secretKey: key,
        ),
        throwsA(isA<CryptoException>()),
      );
    });
  });

  group('pairing secret records', () {
    final engine = EncryptionEngine();
    const secret = 'b64url-256-bit-random-secret';

    test('a new record is a plain SHA-256 that verifies', () async {
      // The bug this pins: every check ran a 64 MiB Argon2id derivation for a
      // secret too random to brute-force, an allocation any peer naming a
      // paired device id could trigger.
      final record = await engine.hashSecret(secret);

      expect(record, startsWith('${EncryptionEngine.sha256HashPrefix}:'));
      expect(
        await engine.verifySecret(secret: secret, encodedHash: record),
        isTrue,
      );
      expect(
        await engine.verifySecret(secret: '${secret}x', encodedHash: record),
        isFalse,
      );
    });

    test(
      'a record stored as Argon2id before the switch still verifies',
      () async {
        final legacyEngine = EncryptionEngine(
          kdf: Argon2id(
            parallelism: 1,
            memory: 1024,
            iterations: 1,
            hashLength: 32,
          ),
        );
        final salt = legacyEngine.generateSalt();
        final key = await legacyEngine.deriveMasterKey(
          masterPassword: secret,
          salt: salt,
        );
        final record = [
          EncryptionEngine.argon2idHashPrefix,
          base64UrlNoPad(salt),
          base64UrlNoPad(await key.extractBytes()),
        ].join(':');

        expect(
          await legacyEngine.verifySecret(secret: secret, encodedHash: record),
          isTrue,
        );
        expect(
          await legacyEngine.verifySecret(secret: 'wrong', encodedHash: record),
          isFalse,
        );
      },
    );

    test('a malformed record never verifies', () async {
      for (final record in ['', 'sha256-v1', 'sha256-v1:!!!', 'md5:abc']) {
        expect(
          await engine.verifySecret(secret: secret, encodedHash: record),
          isFalse,
          reason: record,
        );
      }
    });
  });
}
