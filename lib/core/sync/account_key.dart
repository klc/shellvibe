import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../crypto/encryption_engine.dart';
import 'backup_envelope.dart';

/// The account key, and the record that lets a passphrase or a recovery code
/// reach it.
///
/// Before this, the passphrase was the working secret: every device stored it
/// and sealed each backup with it. Now a device holds a random 256-bit key
/// instead, and the passphrase and recovery code only *wrap* that key. They
/// are typed when no other device is at hand -- recovery, the web panel -- and
/// are not kept anywhere.
///
/// The record is what holds the wrapped copies. One per account, stored on the
/// server and copied into every envelope so a backup stays openable on its
/// own:
///
/// ```
/// {"v": 1, "body": "<json>", "mac": "<base64>"}
/// body = {"pass": {"salt", "wrapped"}, "recovery": {"salt", "wrapped"}?}
/// wrapped = AES-256-GCM(Argon2id(secret, salt), base64(accountKey))
/// mac     = HMAC-SHA256(HKDF(accountKey, "…/record-mac/v1"), utf8(body))
/// ```
///
/// The MAC is over the body's exact bytes, which is why the body travels as a
/// string: nothing has to agree on a canonical JSON form. It lets a device
/// that holds the key tell that a record belongs to it without knowing the
/// passphrase -- so a record handed over by the server is checked before it
/// is copied into a backup, and a key handed over by another device is checked
/// before it is stored.
final class AccountKeyRecord {
  final EncryptionEngine _crypto;

  AccountKeyRecord({EncryptionEngine? crypto})
    : _crypto = crypto ?? EncryptionEngine();

  /// Bytes in an account key.
  static const int keyBytes = 32;

  static const int _version = 1;

  /// A fresh account key. Random, and constant for the life of the account.
  Uint8List generateKey() => _crypto.generateKey(keyBytes);

  /// The key envelopes wrap their payload key under.
  ///
  /// Derived rather than the account key itself, so the key that wraps and the
  /// key that authenticates the record are never the same bytes.
  static Future<SecretKey> wrapKey(Uint8List accountKey) =>
      _derive(accountKey, 'shellvibe/account-key/wrap/v1');

  static Future<SecretKey> _macKey(Uint8List accountKey) =>
      _derive(accountKey, 'shellvibe/account-key/record-mac/v1');

  static Future<SecretKey> _derive(Uint8List accountKey, String info) => Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  ).deriveKey(secretKey: SecretKey(accountKey), info: utf8.encode(info));

  /// A record for [accountKey] that [passphrase] opens, and [recoveryCode]
  /// too when one is given.
  Future<String> build({
    required Uint8List accountKey,
    required String passphrase,
    String? recoveryCode,
  }) async {
    if (passphrase.isEmpty) {
      throw const BackupEnvelopeException('The passphrase cannot be empty.');
    }

    return _seal(accountKey, {
      'pass': await _slot(accountKey, passphrase),
      if (recoveryCode != null && recoveryCode.isNotEmpty)
        'recovery': await _slot(
          accountKey,
          BackupEnvelope.normalizeRecoveryCode(recoveryCode),
        ),
    });
  }

  /// [recordJson] with its recovery slot set to [recoveryCode].
  ///
  /// Needs the key and not the passphrase: the passphrase slot is carried over
  /// as it is. Throws when the record is not [accountKey]'s, because signing a
  /// record this device cannot vouch for would make it look checked.
  Future<String> withRecoveryCode({
    required String recordJson,
    required Uint8List accountKey,
    required String recoveryCode,
  }) async {
    if (!await belongsTo(recordJson, accountKey)) {
      throw const BackupEnvelopeException(
        'The account key record does not belong to this account key.',
      );
    }

    final body = _body(recordJson)!;

    return _seal(accountKey, {
      ...body,
      'recovery': await _slot(
        accountKey,
        BackupEnvelope.normalizeRecoveryCode(recoveryCode),
      ),
    });
  }

  /// The account key, unwrapped with [secret].
  ///
  /// Throws [BackupEnvelopeException] for a wrong secret, a missing slot, an
  /// altered record or one this build does not understand -- the same
  /// exception for all of them, as an envelope does.
  Future<Uint8List> open({
    required String recordJson,
    required String secret,
    BackupUnlockMethod method = BackupUnlockMethod.passphrase,
  }) async {
    final usingRecovery = method == BackupUnlockMethod.recoveryCode;
    final slot = _body(recordJson)?[usingRecovery ? 'recovery' : 'pass'];

    if (slot is! Map<String, dynamic> ||
        slot['salt'] is! String ||
        slot['wrapped'] is! String) {
      throw BackupEnvelopeException(
        usingRecovery
            ? 'This account has no recovery code; use the passphrase.'
            : 'The account key record is missing its passphrase slot.',
      );
    }

    final Uint8List accountKey;
    try {
      final key = await _crypto.deriveMasterKeyInBackground(
        masterPassword: usingRecovery
            ? BackupEnvelope.normalizeRecoveryCode(secret)
            : secret,
        salt: Uint8List.fromList(base64.decode(slot['salt'] as String)),
      );
      accountKey = Uint8List.fromList(
        base64.decode(
          await _crypto.decrypt(
            encryptedBase64: slot['wrapped'] as String,
            secretKey: key,
          ),
        ),
      );
    } on Object {
      throw const BackupEnvelopeException(
        'The passphrase or recovery code is wrong, or the account key record '
        'has been altered.',
      );
    }

    // The slot opened, so the secret is right -- but a slot can be lifted
    // from one record into another. The MAC ties it to the rest.
    if (!await belongsTo(recordJson, accountKey)) {
      throw const BackupEnvelopeException(
        'The passphrase or recovery code is wrong, or the account key record '
        'has been altered.',
      );
    }

    return accountKey;
  }

  /// Whether [recordJson] was written by a holder of [accountKey].
  Future<bool> belongsTo(String recordJson, Uint8List accountKey) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(recordJson);
    } on FormatException {
      return false;
    }

    if (decoded is! Map<String, dynamic> ||
        decoded['v'] != _version ||
        decoded['body'] is! String ||
        decoded['mac'] is! String) {
      return false;
    }

    final List<int> claimed;
    try {
      claimed = base64.decode(decoded['mac'] as String);
    } on FormatException {
      return false;
    }

    return constantTimeEquals(
      await _mac(accountKey, decoded['body'] as String),
      claimed,
    );
  }

  /// Whether [recordJson] has a recovery slot, without opening anything.
  static bool hasRecoverySlot(String recordJson) =>
      _body(recordJson)?['recovery'] is Map<String, dynamic>;

  Future<Map<String, String>> _slot(Uint8List accountKey, String secret) async {
    final salt = _crypto.generateSalt();
    final key = await _crypto.deriveMasterKeyInBackground(
      masterPassword: secret,
      salt: salt,
    );

    return {
      'salt': base64.encode(salt),
      'wrapped': await _crypto.encrypt(
        plaintext: base64.encode(accountKey),
        secretKey: key,
      ),
    };
  }

  Future<String> _seal(Uint8List accountKey, Map<String, dynamic> slots) async {
    final body = jsonEncode(slots);

    return jsonEncode({
      'v': _version,
      'body': body,
      'mac': base64.encode(await _mac(accountKey, body)),
    });
  }

  static Future<List<int>> _mac(Uint8List accountKey, String body) async =>
      (await Hmac.sha256().calculateMac(
        utf8.encode(body),
        secretKey: await _macKey(accountKey),
      )).bytes;

  /// The slots of [recordJson], or null when it is not a record this build
  /// reads.
  static Map<String, dynamic>? _body(String recordJson) {
    try {
      final decoded = jsonDecode(recordJson);
      if (decoded is! Map<String, dynamic> || decoded['v'] != _version) {
        return null;
      }

      final body = jsonDecode(decoded['body'] as String);

      return body is Map<String, dynamic> ? body : null;
    } on Object {
      return null;
    }
  }
}

/// What a device that has joined the account holds: the key, and the record
/// that goes into each envelope it seals.
@immutable
final class AccountKey {
  final Uint8List bytes;

  /// The account's key record, already checked against [bytes].
  final String record;

  const AccountKey({required this.bytes, required this.record});
}
