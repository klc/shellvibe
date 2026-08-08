import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Exception thrown when cryptographic operations fail.
class CryptoException implements Exception {
  final String message;
  final Object? cause;

  CryptoException(this.message, [this.cause]);

  @override
  String toString() =>
      'CryptoException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Zero-Knowledge E2EE Encryption Engine using Argon2id for Key Derivation (KDF)
/// and AES-256-GCM for payload encryption and decryption.
class EncryptionEngine {
  static const String argon2idHashPrefix = 'argon2id-v1';

  final Argon2id _kdf;
  final AesGcm _cipher;

  /// Initializes the EncryptionEngine with optional KDF and Cipher overrides.
  /// Default KDF: Argon2id with hardened parameters for Master Key protection
  /// - memory: 65536 KiB (64 MiB)
  /// - iterations: 3
  /// - parallelism: 1
  /// - hashLength: 32 bytes (256 bits)
  EncryptionEngine({Argon2id? kdf, AesGcm? cipher})
    : _kdf =
          kdf ??
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
      return await _kdf.deriveKey(secretKey: secretKey, nonce: salt);
    } catch (e) {
      throw CryptoException('Failed to derive master key using Argon2id', e);
    }
  }

  /// Generates a cryptographically secure random salt of [length] bytes (default 16 bytes).
  Uint8List generateSalt([int length = 16]) => _randomBytes(length);

  /// Generates a cryptographically secure random 256-bit Data Encryption Key.
  ///
  /// Use this — never [generateSalt] — when the bytes are used as key material.
  Uint8List generateKey([int length = 32]) => _randomBytes(length);

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  /// Creates a self-contained Argon2id password record.
  ///
  /// The salt and derived bytes are stored together, but the original secret
  /// never leaves this method. The format is
  /// `argon2id-v1:<base64url salt>:<base64url digest>`.
  Future<String> hashSecret(String secret) async {
    final salt = generateSalt();
    final key = await deriveMasterKeyInBackground(
      masterPassword: secret,
      salt: salt,
    );
    final digest = await key.extractBytes();
    return [
      argon2idHashPrefix,
      base64Url.encode(salt).replaceAll('=', ''),
      base64Url.encode(digest).replaceAll('=', ''),
    ].join(':');
  }

  /// Verifies a secret against a record produced by [hashSecret].
  Future<bool> verifySecret({
    required String secret,
    required String encodedHash,
  }) async {
    final parts = encodedHash.split(':');
    if (parts.length != 3 || parts[0] != argon2idHashPrefix) return false;
    try {
      final salt = _decodeBase64Url(parts[1]);
      final expected = _decodeBase64Url(parts[2]);
      final key = await deriveMasterKeyInBackground(
        masterPassword: secret,
        salt: salt,
      );
      final actual = await key.extractBytes();
      return _constantTimeEquals(actual, expected);
    } catch (_) {
      return false;
    }
  }

  static Uint8List _decodeBase64Url(String value) {
    final padding = (4 - value.length % 4) % 4;
    return Uint8List.fromList(
      base64Url.decode('$value${List.filled(padding, '=').join()}'),
    );
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = left.length < right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
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

  /// Derives a 256-bit [SecretKey] in a background isolate to avoid
  /// blocking the UI thread during the expensive Argon2id computation.
  ///
  /// KDF parameters are duplicated inline because [Isolate.run] closures
  /// cannot capture non-sendable instance fields.
  Future<SecretKey> deriveMasterKeyInBackground({
    required String masterPassword,
    required Uint8List salt,
  }) async {
    // Avoid isolate spawning overhead in test environments with low KDF memory
    if (_kdf.memory <= 4096) {
      return deriveMasterKey(masterPassword: masterPassword, salt: salt);
    }

    try {
      final parallelism = _kdf.parallelism;
      final memory = _kdf.memory;
      final iterations = _kdf.iterations;
      final hashLength = _kdf.hashLength;

      final keyBytes = await Isolate.run(() async {
        final kdf = Argon2id(
          parallelism: parallelism,
          memory: memory,
          iterations: iterations,
          hashLength: hashLength,
        );
        final passwordBytes = utf8.encode(masterPassword);
        final secretKey = SecretKey(passwordBytes);
        final derivedKey = await kdf.deriveKey(
          secretKey: secretKey,
          nonce: salt,
        );
        return await derivedKey.extractBytes();
      });
      return SecretKey(keyBytes);
    } catch (e) {
      throw CryptoException(
        'Failed to derive master key in background isolate',
        e,
      );
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

      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));

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
