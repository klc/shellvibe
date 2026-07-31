import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Exception thrown when cryptographic operations fail.
class CryptoException implements Exception {
  final String message;
  final Object? cause;

  CryptoException(this.message, [this.cause]);

  @override
  String toString() => 'CryptoException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Zero-Knowledge E2EE Encryption Engine using Argon2id for Key Derivation (KDF)
/// and AES-256-GCM for payload encryption and decryption.
class EncryptionEngine {
  final Argon2id _kdf;
  final AesGcm _cipher;

  /// Initializes the EncryptionEngine with optional KDF and Cipher overrides.
  /// Default KDF: Argon2id with hardened parameters for Master Key protection
  /// - memory: 65536 KiB (64 MiB)
  /// - iterations: 3
  /// - parallelism: 1
  /// - hashLength: 32 bytes (256 bits)
  EncryptionEngine({
    Argon2id? kdf,
    AesGcm? cipher,
  })  : _kdf = kdf ??
            Argon2id(
              parallelism: 1,
              memory: 65536,
              iterations: 3,
              hashLength: 32,
            ),
        _cipher = cipher ?? AesGcm.with256bits();

  /// Derives a 256-bit [SecretKey] from a master password and salt using Argon2id.
  Future<SecretKey> deriveMasterKey({
    required String masterPassword,
    required Uint8List salt,
  }) async {
    try {
      final passwordBytes = utf8.encode(masterPassword);
      final secretKey = SecretKey(passwordBytes);
      return await _kdf.deriveKey(
        secretKey: secretKey,
        nonce: salt,
      );
    } catch (e) {
      throw CryptoException('Failed to derive master key using Argon2id', e);
    }
  }

  /// Generates a cryptographically secure random salt of [length] bytes (default 16 bytes).
  Uint8List generateSalt([int length = 16]) {
    final nonce = _cipher.newNonce();
    if (nonce.length >= length) {
      return Uint8List.fromList(nonce.sublist(0, length));
    }
    final builder = BytesBuilder();
    while (builder.length < length) {
      builder.add(_cipher.newNonce());
    }
    return Uint8List.fromList(builder.toBytes().sublist(0, length));
  }

  /// Encrypts a UTF-8 plaintext string using AES-256-GCM.
  ///
  /// Returns a Base64-encoded payload string structured as:
  /// `[12 bytes Nonce] + [16 bytes MAC] + [Ciphertext]`
  Future<String> encrypt({
    required String plaintext,
    required SecretKey secretKey,
  }) async {
    try {
      final plaintextBytes = utf8.encode(plaintext);
      final nonce = _cipher.newNonce();
      final secretBox = await _cipher.encrypt(
        plaintextBytes,
        secretKey: secretKey,
        nonce: nonce,
      );

      final builder = BytesBuilder();
      builder.add(secretBox.nonce);
      builder.add(secretBox.mac.bytes);
      builder.add(secretBox.cipherText);

      return base64.encode(builder.toBytes());
    } catch (e) {
      throw CryptoException('Failed to encrypt payload using AES-256-GCM', e);
    }
  }

  /// Decrypts a Base64-encoded payload (containing Nonce + MAC + Ciphertext)
  /// using AES-256-GCM.
  ///
  /// Returns the original decrypted UTF-8 plaintext string.
  Future<String> decrypt({
    required String encryptedBase64,
    required SecretKey secretKey,
  }) async {
    try {
      final bytes = base64.decode(encryptedBase64);
      if (bytes.length < 28) {
        throw CryptoException('Invalid ciphertext payload: byte length < 28');
      }

      final nonce = bytes.sublist(0, 12);
      final macBytes = bytes.sublist(12, 28);
      final cipherText = bytes.sublist(28);

      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final decryptedBytes = await _cipher.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return utf8.decode(decryptedBytes);
    } catch (e) {
      if (e is CryptoException) rethrow;
      throw CryptoException('Failed to decrypt payload using AES-256-GCM', e);
    }
  }
}
