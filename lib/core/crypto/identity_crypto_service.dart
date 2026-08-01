import 'package:cryptography/cryptography.dart';
import 'encryption_engine.dart';

/// Service for encrypting and decrypting Identity credential fields
/// (password, privateKey, passphrase) using the vault's master key.
///
/// Used by [VaultIdentities] provider when saving or retrieving
/// credentials for SSH connections.
class IdentityCryptoService {
  final EncryptionEngine _engine;

  IdentityCryptoService(this._engine);

  /// Encrypts a nullable plaintext field. Returns null if input is null or empty.
  Future<String?> encryptField(
    String? plaintext,
    SecretKey masterKey,
  ) async {
    if (plaintext == null || plaintext.isEmpty) return null;
    return await _engine.encrypt(plaintext: plaintext, secretKey: masterKey);
  }

  /// Decrypts a nullable encrypted Base64 field. Returns null if input is null or empty.
  ///
  /// Falls back to returning the original value if decryption fails,
  /// which handles legacy unencrypted data gracefully.
  Future<String?> decryptField(
    String? encryptedBase64,
    SecretKey masterKey,
  ) async {
    if (encryptedBase64 == null || encryptedBase64.isEmpty) return null;
    try {
      return await _engine.decrypt(
        encryptedBase64: encryptedBase64,
        secretKey: masterKey,
      );
    } on CryptoException {
      // Field may not be encrypted yet (legacy data) — return as-is
      return encryptedBase64;
    }
  }
}
