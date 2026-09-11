import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/core/crypto/identity_crypto_service.dart';

void main() {
  group('IdentityCryptoService Unit Tests', () {
    late EncryptionEngine engine;
    late IdentityCryptoService cryptoService;

    setUp(() {
      engine = EncryptionEngine();
      cryptoService = IdentityCryptoService(engine);
    });

    test('encryptField and decryptField roundtrip for valid plaintext', () async {
      final salt = engine.generateSalt(16);
      final masterKey = await engine.deriveMasterKey(
        masterPassword: 'VaultPassword123',
        salt: salt,
      );

      const passwordField = 'MySuperSecretPassword';
      final encrypted = await cryptoService.encryptField(passwordField, masterKey);

      expect(encrypted, isNotNull);
      expect(encrypted, isNot(equals(passwordField)));

      final decrypted = await cryptoService.decryptField(encrypted, masterKey);
      expect(decrypted, equals(passwordField));
    });

    test('encryptField returns null for null or empty input', () async {
      final salt = engine.generateSalt(16);
      final masterKey = await engine.deriveMasterKey(
        masterPassword: 'VaultPassword123',
        salt: salt,
      );

      expect(await cryptoService.encryptField(null, masterKey), isNull);
      expect(await cryptoService.encryptField('', masterKey), isNull);
    });

    test('decryptField returns null for null or empty input', () async {
      final salt = engine.generateSalt(16);
      final masterKey = await engine.deriveMasterKey(
        masterPassword: 'VaultPassword123',
        salt: salt,
      );

      expect(await cryptoService.decryptField(null, masterKey), isNull);
      expect(await cryptoService.decryptField('', masterKey), isNull);
    });

    test('decryptField throws IdentityCryptoException when decryption fails', () async {
      final salt = engine.generateSalt(16);
      final masterKey = await engine.deriveMasterKey(
        masterPassword: 'VaultPassword123',
        salt: salt,
      );

      const invalidOrLegacyText = 'legacy_unencrypted_password_or_key';
      expect(
        () => cryptoService.decryptField(invalidOrLegacyText, masterKey),
        throwsA(isA<IdentityCryptoException>()),
      );
    });
  });
}
