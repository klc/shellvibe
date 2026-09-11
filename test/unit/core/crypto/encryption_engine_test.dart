import 'dart:convert';
import 'dart:typed_data';
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
}
