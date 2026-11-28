import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../crypto/encryption_engine.dart';
import 'account_key.dart';

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
/// * **v4** carries the sync key as well: the long-lived random key that
///   encrypts operations in the log, wrapped under the same payload key. The
///   sync key is deliberately not derived from the passphrase -- deriving it
///   would mean a passphrase change made every operation already in the log
///   unreadable, so the passphrase could either never change or every
///   operation would have to be rewritten.
/// * **v5** wraps the payload key under the account key instead of under each
///   unlocking secret, and carries the account's key record beside it. A
///   device seals it without knowing the passphrase, and the passphrase or
///   the recovery code still opens it: through the record to the account key,
///   and from there to the payload key. See [AccountKeyRecord].
const int kBackupSchemaVersion = 4;

/// The version [BackupEnvelope.sealWithAccountKey] writes, and the newest this
/// build reads.
const int kBackupSchemaVersionAccountKey = 5;

/// The version written when there is no sync key to carry.
///
/// A v4 envelope is refused outright by a build that reads up to v3, so one is
/// only written when it has something a v3 cannot hold. Until automatic sync
/// is set up on a vault, its backups stay readable by older builds.
const int kBackupSchemaVersionWithoutSyncKey = 3;

/// How a v3 envelope was opened.
enum BackupUnlockMethod {
  /// The user's sync passphrase.
  passphrase,

  /// The one-time recovery code shown at setup.
  recoveryCode,

  /// The account key this device holds. No secret was typed.
  accountKey,
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

  /// The vault's sync key, or null for an envelope written before automatic
  /// sync was set up on this vault.
  final SecretKey? syncKey;

  /// The account key a v5 envelope was opened to, whichever way it was
  /// reached. Null below v5, which has none.
  final Uint8List? accountKey;

  /// The key record a v5 envelope carries. Checked against [accountKey] only
  /// when the envelope was opened with a typed secret.
  final String? keyRecord;

  const OpenedBackup({
    required this.payloadJson,
    required this.backupDek,
    required this.unlockedWith,
    required this.schemaVersion,
    this.syncKey,
    this.accountKey,
    this.keyRecord,
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

  /// Bytes drawn for a recovery code, one per character.
  ///
  /// Each byte is reduced to one symbol of a 32-letter alphabet, so the code
  /// carries 5 bits per character: 160 bits over 32 characters. Far past
  /// anything a passphrase policy could ask for, and the reason no policy is
  /// applied to it -- but not the 256 bits the byte count suggests.
  static const int recoveryCodeBytes = 32;

  /// Bytes in a sync key. The same size as the payload key it is wrapped
  /// under, because it protects data of the same value.
  static const int syncKeyBytes = 32;

  /// A fresh sync key. Random, and constant for the lifetime of the vault.
  Uint8List generateSyncKey() => _crypto.generateSalt(syncKeyBytes);

  /// Builds a v3 envelope, or a v4 one when [syncKey] is given.
  ///
  /// [payloadJson] and [dek] are encrypted under a fresh random payload key.
  /// That key is wrapped with [passphrase], and again with [recoveryCode] when
  /// one is given, so either secret opens the backup on its own.
  ///
  /// [syncKey] is wrapped under the payload key rather than under each
  /// unlocking secret in turn. That is one ciphertext instead of two and still
  /// reaches through both paths, because whoever can open the envelope at all
  /// already holds the payload key. It also keeps the property the sync key
  /// exists for: changing the passphrase rewraps 32 bytes and leaves every
  /// operation in the log readable.
  Future<String> seal({
    required String payloadJson,
    required SecretKey dek,
    required String passphrase,
    String? recoveryCode,
    Uint8List? syncKey,
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
      'schema_version': syncKey == null
          ? kBackupSchemaVersionWithoutSyncKey
          : kBackupSchemaVersion,
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
      if (syncKey != null)
        'sync_key_wrapped': await _crypto.encrypt(
          plaintext: base64.encode(syncKey),
          secretKey: payloadKey,
        ),
    });
  }

  /// Builds a v5 envelope, sealed with the account key.
  ///
  /// [keyRecord] is copied in as it is. It is what lets the passphrase or the
  /// recovery code open this envelope with no server to ask, and the caller
  /// has already checked it belongs to [accountKey].
  Future<String> sealWithAccountKey({
    required String payloadJson,
    required SecretKey dek,
    required Uint8List accountKey,
    required String keyRecord,
    Uint8List? syncKey,
  }) async {
    final payloadKeyBytes = _crypto.generateSalt(32);
    final payloadKey = SecretKey(payloadKeyBytes);

    return jsonEncode({
      'schema_version': kBackupSchemaVersionAccountKey,
      'payload': await _crypto.encrypt(
        plaintext: payloadJson,
        secretKey: payloadKey,
      ),
      'dek_wrapped': await _crypto.encrypt(
        plaintext: base64.encode(await dek.extractBytes()),
        secretKey: payloadKey,
      ),
      'pk_wrapped_ak': await _crypto.encrypt(
        plaintext: base64.encode(payloadKeyBytes),
        secretKey: await AccountKeyRecord.wrapKey(accountKey),
      ),
      'key_record': keyRecord,
      if (syncKey != null)
        'sync_key_wrapped': await _crypto.encrypt(
          plaintext: base64.encode(syncKey),
          secretKey: payloadKey,
        ),
    });
  }

  /// Opens an envelope of any version this build reads.
  ///
  /// With [accountKey], a v5 envelope opens directly and [secret] is not
  /// looked at. Without it, [secret] opens every version, and [method] says
  /// whether it is the passphrase or the recovery code; v1 and v2 have only
  /// the passphrase.
  ///
  /// Throws [BackupEnvelopeException] for a wrong secret, a tampered envelope,
  /// a malformed one, or a version this build does not know -- deliberately the
  /// same exception for all of them.
  Future<OpenedBackup> open({
    required String envelopeJson,
    String? secret,
    BackupUnlockMethod method = BackupUnlockMethod.passphrase,
    Uint8List? accountKey,
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
    if (schemaVersion > kBackupSchemaVersionAccountKey) {
      throw BackupEnvelopeException(
        'This backup was written by a newer version of ShellVibe '
        '(envelope v$schemaVersion, this build reads up to '
        'v$kBackupSchemaVersionAccountKey).',
      );
    }

    if (schemaVersion >= kBackupSchemaVersionAccountKey) {
      return _openV5(envelope, secret, method, accountKey, schemaVersion);
    }

    if (secret == null) {
      throw BackupEnvelopeException(
        'This backup was sealed with the passphrase, before the account key '
        'existed (envelope v$schemaVersion). Open it with the passphrase.',
      );
    }

    return schemaVersion >= 3
        ? _openV3(envelope, secret, method, schemaVersion)
        : _openLegacy(envelope, secret, schemaVersion);
  }

  /// Whether [schemaVersion] is one an account key opens.
  static bool opensWithAccountKey(int schemaVersion) =>
      schemaVersion >= kBackupSchemaVersionAccountKey;

  /// The schema version [envelopeJson] declares, without opening it.
  ///
  /// The sealed envelope decides its own version -- v3 when it carries no sync
  /// key, v4 when it does -- so the number that travels beside it in the
  /// upload metadata has to be read back off it rather than assumed from this
  /// build's newest. Sending [kBackupSchemaVersion] for a v3 envelope tells
  /// every reader, including the restore list, that a backup an older build
  /// could open is one it must refuse.
  ///
  /// Falls back to 1: an envelope whose version cannot be read is the oldest
  /// thing it could be, and claiming otherwise would refuse it on a build that
  /// can in fact open it.
  static int versionOf(String envelopeJson) {
    try {
      final decoded = jsonDecode(envelopeJson);

      return decoded is Map<String, dynamic>
          ? decoded['schema_version'] as int? ?? 1
          : 1;
    } on Object {
      return 1;
    }
  }

  /// Whether [envelopeJson] carries a recovery-code path, without opening it.
  ///
  /// Lets a restore screen offer the recovery option only when the backup
  /// actually has one, rather than after a failed attempt.
  static bool hasRecoveryPath(String envelopeJson) {
    try {
      final decoded = jsonDecode(envelopeJson);

      if (decoded is! Map<String, dynamic>) return false;

      final record = decoded['key_record'];
      if (record is String) return AccountKeyRecord.hasRecoverySlot(record);

      return decoded['pk_wrapped_recovery'] is String &&
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

    final wrappedSyncKey = envelope['sync_key_wrapped'] as String?;

    return OpenedBackup(
      payloadJson: await _decryptOrFail(encrypted: payload, key: payloadKey),
      backupDek: SecretKey(
        base64.decode(
          await _decryptOrFail(encrypted: wrappedDek, key: payloadKey),
        ),
      ),
      unlockedWith: method,
      schemaVersion: schemaVersion,
      syncKey: wrappedSyncKey == null
          ? null
          : SecretKey(
              base64.decode(
                await _decryptOrFail(
                  encrypted: wrappedSyncKey,
                  key: payloadKey,
                ),
              ),
            ),
    );
  }

  Future<OpenedBackup> _openV5(
    Map<String, dynamic> envelope,
    String? secret,
    BackupUnlockMethod method,
    Uint8List? accountKey,
    int schemaVersion,
  ) async {
    final payload = envelope['payload'] as String?;
    final wrappedDek = envelope['dek_wrapped'] as String?;
    final wrappedKey = envelope['pk_wrapped_ak'] as String?;
    final keyRecord = envelope['key_record'] as String?;
    if (payload == null || wrappedDek == null || wrappedKey == null) {
      throw const BackupEnvelopeException('The backup envelope is incomplete.');
    }

    final Uint8List key;
    if (accountKey != null) {
      key = accountKey;
    } else {
      if (secret == null || keyRecord == null) {
        throw const BackupEnvelopeException(
          'The backup is missing its account key record.',
        );
      }

      key = await AccountKeyRecord(
        crypto: _crypto,
      ).open(recordJson: keyRecord, secret: secret, method: method);
    }

    final payloadKey = SecretKey(
      base64.decode(
        await _decryptOrFail(
          encrypted: wrappedKey,
          key: await AccountKeyRecord.wrapKey(key),
        ),
      ),
    );

    final wrappedSyncKey = envelope['sync_key_wrapped'] as String?;

    return OpenedBackup(
      payloadJson: await _decryptOrFail(encrypted: payload, key: payloadKey),
      backupDek: SecretKey(
        base64.decode(
          await _decryptOrFail(encrypted: wrappedDek, key: payloadKey),
        ),
      ),
      unlockedWith: accountKey != null ? BackupUnlockMethod.accountKey : method,
      schemaVersion: schemaVersion,
      syncKey: wrappedSyncKey == null
          ? null
          : SecretKey(
              base64.decode(
                await _decryptOrFail(
                  encrypted: wrappedSyncKey,
                  key: payloadKey,
                ),
              ),
            ),
      accountKey: key,
      keyRecord: keyRecord,
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
