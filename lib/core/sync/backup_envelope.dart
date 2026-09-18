import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../crypto/encryption_engine.dart';

/// Envelope format version produced by [BackupEnvelope.seal].
///
/// * **v1** carried identity ciphertext only. The key that could decrypt it
///   stayed in the exporting device's keychain, so the secrets were
///   unrecoverable anywhere else.
/// * **v2** added the vault Data Encryption Key, wrapped with the backup
///   password, making the backup self-contained. The payload itself was still
///   encrypted directly under the password-derived key, so exactly one secret
///   could ever open it.
/// * **v3** puts a random payload key in between. The payload and the vault DEK
///   are encrypted under that key, and the key itself is wrapped once per
///   unlocking secret. Two consequences follow, and both are the reason for the
///   version: a recovery code can open the same backup as the passphrase, and
///   changing the passphrase rewraps a 32-byte key instead of re-encrypting the
///   whole payload.
const int kBackupSchemaVersion = 3;

/// How a v3 envelope was opened.
enum BackupUnlockMethod {
  /// The user's sync passphrase.
  passphrase,

  /// The one-time recovery code shown at setup.
  recoveryCode,
}

/// A sealed envelope could not be opened, or is not one this build understands.
///
/// Carries no detail about *which* check failed beyond [reason]: a caller that
/// could tell "wrong passphrase" from "tampered ciphertext" by the exception
/// type would be an oracle, and the user-facing answer is the same either way.
@immutable
final class BackupEnvelopeException implements Exception {
  final String reason;

  const BackupEnvelopeException(this.reason);

  @override
  String toString() => 'BackupEnvelopeException: $reason';
}

/// The contents of an opened envelope.
@immutable
final class OpenedBackup {
  /// The decrypted payload JSON, exactly as it was sealed.
  final String payloadJson;

  /// The vault Data Encryption Key the backup was written with, or null for a
  /// v1 envelope that carried none.
  final SecretKey? backupDek;

  /// Which secret opened it.
  final BackupUnlockMethod unlockedWith;

  /// The envelope's own schema version.
  final int schemaVersion;

  const OpenedBackup({
    required this.payloadJson,
    required this.backupDek,
    required this.unlockedWith,
    required this.schemaVersion,
  });

  /// True for a v1 envelope, whose identity secrets cannot be decrypted on any
  /// device but the one that wrote them.
  bool get isLegacyWithoutKey => backupDek == null;
}

/// Seals and opens the encrypted backup envelope.
///
/// Keeps the key schedule in one place, separate from what the payload happens
/// to contain. The payload is opaque here on purpose: this class never learns
/// what a host or an identity is, and the service that does never handles a
/// wrapped key.
final class BackupEnvelope {
  final EncryptionEngine _crypto;

  BackupEnvelope({EncryptionEngine? crypto})
    : _crypto = crypto ?? EncryptionEngine();

  /// Bytes in a recovery code before encoding. 256 bits, so the code itself is
  /// as strong as the key it protects and no passphrase policy applies to it.
  static const int recoveryCodeBytes = 32;

  /// Builds a v3 envelope.
  ///
  /// [payloadJson] and [dek] are encrypted under a fresh random payload key.
  /// That key is wrapped with [passphrase], and again with [recoveryCode] when
  /// one is given, so either secret opens the backup on its own.
  Future<String> seal({
    required String payloadJson,
    required SecretKey dek,
    required String passphrase,
    String? recoveryCode,
  }) async {
    if (passphrase.isEmpty) {
      throw const BackupEnvelopeException('The passphrase cannot be empty.');
    }

    final payloadKeyBytes = _crypto.generateSalt(32);
    final payloadKey = SecretKey(payloadKeyBytes);
    final payloadKeyBase64 = base64.encode(payloadKeyBytes);

    final passphraseSalt = _crypto.generateSalt();
    final passphraseKey = await _crypto.deriveMasterKeyInBackground(
      masterPassword: passphrase,
      salt: passphraseSalt,
    );

    Uint8List? recoverySalt;
    String? recoveryWrapped;
    if (recoveryCode != null && recoveryCode.isNotEmpty) {
      recoverySalt = _crypto.generateSalt();
      final recoveryKey = await _crypto.deriveMasterKeyInBackground(
        masterPassword: normalizeRecoveryCode(recoveryCode),
        salt: recoverySalt,
      );
      recoveryWrapped = await _crypto.encrypt(
        plaintext: payloadKeyBase64,
        secretKey: recoveryKey,
      );
    }

    return jsonEncode({
      'schema_version': kBackupSchemaVersion,
      'salt': base64.encode(passphraseSalt),
      'recovery_salt': recoverySalt == null
          ? null
          : base64.encode(recoverySalt),
      'payload': await _crypto.encrypt(
        plaintext: payloadJson,
        secretKey: payloadKey,
      ),
      'dek_wrapped': await _crypto.encrypt(
        plaintext: base64.encode(await dek.extractBytes()),
        secretKey: payloadKey,
      ),
      'pk_wrapped_pass': await _crypto.encrypt(
        plaintext: payloadKeyBase64,
        secretKey: passphraseKey,
      ),
      'pk_wrapped_recovery': recoveryWrapped,
    });
  }

  /// Opens a v1, v2 or v3 envelope with [secret].
  ///
  /// [method] selects which wrapped key a v3 envelope is opened through. It is
  /// ignored for v1 and v2, which have only one.
  ///
  /// Throws [BackupEnvelopeException] for a wrong secret, a tampered envelope,
  /// a malformed one, or a version this build does not know -- deliberately the
  /// same exception for all of them.
  Future<OpenedBackup> open({
    required String envelopeJson,
    required String secret,
    BackupUnlockMethod method = BackupUnlockMethod.passphrase,
  }) async {
    final Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(envelopeJson);
      if (decoded is! Map<String, dynamic>) {
        throw const BackupEnvelopeException('The backup is not an envelope.');
      }
      envelope = decoded;
    } on FormatException {
      throw const BackupEnvelopeException('The backup file is not valid JSON.');
    }

    final schemaVersion = envelope['schema_version'] as int? ?? 1;
    if (schemaVersion > kBackupSchemaVersion) {
      throw BackupEnvelopeException(
        'This backup was written by a newer version of ShellVibe '
        '(envelope v$schemaVersion, this build reads up to '
        'v$kBackupSchemaVersion).',
      );
    }

    return schemaVersion >= 3
        ? _openV3(envelope, secret, method, schemaVersion)
        : _openLegacy(envelope, secret, schemaVersion);
  }

  /// Whether [envelopeJson] carries a recovery-code path, without opening it.
  ///
  /// Lets a restore screen offer the recovery option only when the backup
  /// actually has one, rather than after a failed attempt.
  static bool hasRecoveryPath(String envelopeJson) {
    try {
      final decoded = jsonDecode(envelopeJson);

      return decoded is Map<String, dynamic> &&
          decoded['pk_wrapped_recovery'] is String &&
          decoded['recovery_salt'] is String;
    } on FormatException {
      return false;
    }
  }

  /// A fresh recovery code, grouped for reading aloud and typing back.
  ///
  /// Crockford base32 without the ambiguous letters, in groups of five:
  /// `X4K7M-9PQR2-...`. It is never stored anywhere; the user writes it down
  /// at setup or loses the ability to recover.
  String generateRecoveryCode() {
    final bytes = _crypto.generateSalt(recoveryCodeBytes);
    final buffer = StringBuffer();

    for (var i = 0; i < bytes.length; i++) {
      if (i > 0 && i % 5 == 0) buffer.write('-');
      buffer.write(_alphabet[bytes[i] % _alphabet.length]);
    }

    return buffer.toString();
  }

  /// Canonical form of a typed recovery code.
  ///
  /// Grouping dashes, spaces and case are presentation, so they are stripped
  /// before key derivation. Otherwise a user who types their code without the
  /// dashes -- exactly what a paste from a password manager does -- derives a
  /// different key and is told their correct code is wrong.
  static String normalizeRecoveryCode(String input) =>
      input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  Future<OpenedBackup> _openV3(
    Map<String, dynamic> envelope,
    String secret,
    BackupUnlockMethod method,
    int schemaVersion,
  ) async {
    final usingRecovery = method == BackupUnlockMethod.recoveryCode;

    final saltBase64 =
        (usingRecovery ? envelope['recovery_salt'] : envelope['salt'])
            as String?;
    final wrappedKey =
        (usingRecovery
                ? envelope['pk_wrapped_recovery']
                : envelope['pk_wrapped_pass'])
            as String?;

    if (saltBase64 == null || wrappedKey == null) {
      throw BackupEnvelopeException(
        usingRecovery
            ? 'This backup has no recovery code; open it with the passphrase.'
            : 'The backup is missing its passphrase key.',
      );
    }

    final payload = envelope['payload'] as String?;
    final wrappedDek = envelope['dek_wrapped'] as String?;
    if (payload == null || wrappedDek == null) {
      throw const BackupEnvelopeException('The backup envelope is incomplete.');
    }

    final unwrapKey = await _crypto.deriveMasterKeyInBackground(
      masterPassword: usingRecovery ? normalizeRecoveryCode(secret) : secret,
      salt: Uint8List.fromList(base64.decode(saltBase64)),
    );

    final payloadKey = SecretKey(
      base64.decode(
        await _decryptOrFail(encrypted: wrappedKey, key: unwrapKey),
      ),
    );

    return OpenedBackup(
      payloadJson: await _decryptOrFail(encrypted: payload, key: payloadKey),
      backupDek: SecretKey(
        base64.decode(
          await _decryptOrFail(encrypted: wrappedDek, key: payloadKey),
        ),
      ),
      unlockedWith: method,
      schemaVersion: schemaVersion,
    );
  }

  /// Opens a v1 or v2 envelope, where the payload is encrypted directly under
  /// the password-derived key and there is no recovery path.
  Future<OpenedBackup> _openLegacy(
    Map<String, dynamic> envelope,
    String secret,
    int schemaVersion,
  ) async {
    final saltBase64 = envelope['salt'] as String?;
    final payload = envelope['payload'] as String?;
    if (saltBase64 == null || payload == null) {
      throw const BackupEnvelopeException('The backup envelope is incomplete.');
    }

    final wrappedDek = envelope['dek_wrapped'] as String?;
    if (schemaVersion >= 2 && wrappedDek == null) {
      throw const BackupEnvelopeException(
        'This v2 backup is missing the wrapped vault key.',
      );
    }

    final key = await _crypto.deriveMasterKeyInBackground(
      masterPassword: secret,
      salt: Uint8List.fromList(base64.decode(saltBase64)),
    );

    return OpenedBackup(
      payloadJson: await _decryptOrFail(encrypted: payload, key: key),
      backupDek: wrappedDek == null
          ? null
          : SecretKey(
              base64.decode(
                await _decryptOrFail(encrypted: wrappedDek, key: key),
              ),
            ),
      unlockedWith: BackupUnlockMethod.passphrase,
      schemaVersion: schemaVersion,
    );
  }

  /// Decrypts, turning every failure into one exception.
  ///
  /// AES-GCM authenticates, so a wrong key and a flipped ciphertext byte both
  /// fail the tag check and arrive here identically -- which is the point.
  /// Nothing partial is ever returned.
  Future<String> _decryptOrFail({
    required String encrypted,
    required SecretKey key,
  }) async {
    try {
      return await _crypto.decrypt(encryptedBase64: encrypted, secretKey: key);
    } on Object {
      throw const BackupEnvelopeException(
        'The backup could not be opened. The passphrase or recovery code is '
        'wrong, or the file has been altered.',
      );
    }
  }

  /// Crockford-style base32 with `I`, `L`, `O` and `U` removed, so a
  /// handwritten code cannot be misread as a digit or a different letter.
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
}
