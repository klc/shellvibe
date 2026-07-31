import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/core/crypto/encryption_engine.dart';

void main() {
  group('EncryptionEngine Unit Tests', () {
    late EncryptionEngine cryptoEngine;

    setUp(() {
      cryptoEngine = EncryptionEngine();
    });

    test('generateSalt produces salt of requested length', () {
      final salt16 = cryptoEngine.generateSalt(16);
      expect(salt16.length, equals(16));

      final salt32 = cryptoEngine.generateSalt(32);
      expect(salt32.length, equals(32));

      // Salt should be random (not identical)
      final saltAnother = cryptoEngine.generateSalt(16);
      expect(salt16, isNot(equals(saltAnother)));
    });

    test('deriveMasterKey derives key consistently from password and salt', () async {
      final password = 'SuperSecretMasterPassword123!';
      final salt = cryptoEngine.generateSalt(16);

      final key1 = await cryptoEngine.deriveMasterKey(
        masterPassword: password,
        salt: salt,
      );

      final key2 = await cryptoEngine.deriveMasterKey(
        masterPassword: password,
        salt: salt,
      );

      final bytes1 = await key1.extractBytes();
      final bytes2 = await key2.extractBytes();

      expect(bytes1.length, equals(32)); // 256 bits
      expect(bytes1, equals(bytes2));
    });

    test('deriveMasterKey produces different key with different password or salt', () async {
      final salt = cryptoEngine.generateSalt(16);

      final key1 = await cryptoEngine.deriveMasterKey(
        masterPassword: 'Password1',
        salt: salt,
      );

      final key2 = await cryptoEngine.deriveMasterKey(
        masterPassword: 'Password2',
        salt: salt,
      );

      final bytes1 = await key1.extractBytes();
      final bytes2 = await key2.extractBytes();

      expect(bytes1, isNot(equals(bytes2)));
    });

    test('AES-256-GCM encrypt and decrypt roundtrip success', () async {
      final password = 'TestMasterPassword!';
      final salt = cryptoEngine.generateSalt(16);
      final key = await cryptoEngine.deriveMasterKey(
        masterPassword: password,
        salt: salt,
      );

      final originalText = 'SSH Private Key Content -- RSA 4096 -- SECRET!';
      final encryptedBase64 = await cryptoEngine.encrypt(
        plaintext: originalText,
        secretKey: key,
      );

      expect(encryptedBase64, isNotEmpty);
      expect(encryptedBase64, isNot(equals(originalText)));

      final decryptedText = await cryptoEngine.decrypt(
        encryptedBase64: encryptedBase64,
        secretKey: key,
      );

      expect(decryptedText, equals(originalText));
    });

    test('AES-256-GCM decryption throws CryptoException on tampered ciphertext', () async {
      final salt = cryptoEngine.generateSalt(16);
      final key = await cryptoEngine.deriveMasterKey(
        masterPassword: 'Password',
        salt: salt,
      );

      final originalText = 'Sensitive password';
      final encryptedBase64 = await cryptoEngine.encrypt(
        plaintext: originalText,
        secretKey: key,
      );

      // Tamper ciphertext
      final rawBytes = base64.decode(encryptedBase64);
      rawBytes[rawBytes.length - 1] ^= 0xFF; // Flip bits in last byte
      final tamperedBase64 = base64.encode(rawBytes);

      expect(
        () => cryptoEngine.decrypt(
          encryptedBase64: tamperedBase64,
          secretKey: key,
        ),
        throwsA(isA<CryptoException>()),
      );
    });

    test('AES-256-GCM decryption throws CryptoException on short payload', () async {
      final salt = cryptoEngine.generateSalt(16);
      final key = await cryptoEngine.deriveMasterKey(
        masterPassword: 'Password',
        salt: salt,
      );

      final shortPayload = base64.encode(Uint8List(10)); // < 28 bytes

      expect(
        () => cryptoEngine.decrypt(
          encryptedBase64: shortPayload,
          secretKey: key,
        ),
        throwsA(isA<CryptoException>()),
      );
    });
  });
}
