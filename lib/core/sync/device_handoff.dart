import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../crypto/encryption_engine.dart';

/// Passing the account key from a device that holds it to one that does not.
///
/// One device shows a QR code, the other scans it, and from then on they talk
/// through a mailbox on the server. The code is what makes that safe: it is
/// read off the screen of a device the user is holding, so it carries the
/// things the server must not be able to choose or learn.
///
/// ```
/// QR      = {id, displayer's one-time X25519 public key, 32-byte secret, user}
/// shared  = X25519(scanner's one-time key, displayer's public key)
/// keys    = HKDF(shared, salt: secret, info: id | user | both keys | direction)
/// offer   = scanner's public key + AES-256-GCM(keys.offer, payload)
/// answer  = AES-256-GCM(keys.answer, payload)
/// ```
///
/// The server carries `offer` and `answer` and sees nothing else. It cannot
/// read them -- it has neither private key nor the secret -- and it cannot
/// swap the scanner's public key for its own, because the offer is sealed
/// under a key that needs the secret from the code. A swapped key derives
/// different keys and the offer fails to open.
///
/// Either side can be the one that holds the account key. A phone joining
/// from a desktop scans the desktop's code and reads the key from the answer;
/// a desktop joining from a phone shows a code and reads the key from the
/// offer. Whichever way, the key crosses once, in one message.
///
/// What the code does not survive is being photographed *and* used, by
/// someone signed in to the same account, before the real device gets there.
/// So it is short-lived, the mailbox takes one offer, and nothing in it is the
/// passphrase: a code that leaks after the handoff opens nothing.
abstract final class DeviceHandoff {
  static const String _context = 'shellvibe/handoff/v1';

  static final X25519 _exchange = X25519();

  /// Opens a handoff on the device that shows the code.
  ///
  /// [gives] says which way the key goes: true when this device holds it.
  static Future<HandoffDisplay> display({
    required String id,
    required String userId,
    required bool gives,
    required DateTime expiresAt,
  }) async {
    final keyPair = await _exchange.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();

    return HandoffDisplay._(
      keyPair,
      HandoffInvite(
        id: id,
        userId: userId,
        publicKey: Uint8List.fromList(publicKey.bytes),
        secret: secureRandomBytes(32),
        displayerGives: gives,
        expiresAt: expiresAt.toUtc(),
      ),
    );
  }

  /// Takes up a scanned [invite] on the device that scanned it.
  ///
  /// Refuses a code from another account or one that has run out before
  /// anything is derived from it.
  static Future<HandoffScan> scan(
    HandoffInvite invite, {
    required String userId,
    DateTime? now,
  }) async {
    if (invite.userId != userId) {
      throw const HandoffException(
        'This code belongs to another account. Sign in to the same account '
        'on both devices.',
      );
    }
    if (!(now ?? DateTime.now()).toUtc().isBefore(invite.expiresAt)) {
      throw const HandoffException('This code has expired. Show a new one.');
    }

    final keyPair = await _exchange.newKeyPair();
    final publicKey = Uint8List.fromList(
      (await keyPair.extractPublicKey()).bytes,
    );

    return HandoffScan._(
      invite,
      publicKey,
      await _keys(
        invite: invite,
        own: keyPair,
        remote: invite.publicKey,
        scannerPublicKey: publicKey,
      ),
    );
  }

  static Future<_HandoffKeys> _keys({
    required HandoffInvite invite,
    required SimpleKeyPair own,
    required Uint8List remote,
    required Uint8List scannerPublicKey,
  }) async {
    final shared = await _exchange.sharedSecretKey(
      keyPair: own,
      remotePublicKey: SimplePublicKey(remote, type: KeyPairType.x25519),
    );

    final material = await Hkdf(hmac: Hmac.sha256(), outputLength: 64)
        .deriveKey(
          secretKey: shared,
          nonce: invite.secret,
          // Everything both sides agree on. A message lifted into another
          // handoff, another account or the other direction derives other
          // keys and does not open.
          info: utf8.encode(
            jsonEncode([
              _context,
              invite.id,
              invite.userId,
              base64.encode(invite.publicKey),
              base64.encode(scannerPublicKey),
              invite.displayerGives,
            ]),
          ),
        );
    final bytes = await material.extractBytes();

    return _HandoffKeys(
      offer: SecretKey(bytes.sublist(0, 32)),
      answer: SecretKey(bytes.sublist(32)),
    );
  }
}

/// What the QR code carries.
@immutable
final class HandoffInvite {
  static const String _type = 'shellvibe-handoff';
  static const int _version = 1;

  /// The mailbox on the server.
  final String id;

  /// The account both devices have to be signed in to.
  final String userId;

  /// The displaying device's one-time public key.
  final Uint8List publicKey;

  /// Never sent to the server. See [DeviceHandoff].
  final Uint8List secret;

  /// True when the device showing the code is the one that holds the key.
  final bool displayerGives;

  final DateTime expiresAt;

  const HandoffInvite({
    required this.id,
    required this.userId,
    required this.publicKey,
    required this.secret,
    required this.displayerGives,
    required this.expiresAt,
  });

  String encode() => jsonEncode({
    't': _type,
    'v': _version,
    'id': id,
    'u': userId,
    'pk': base64UrlNoPad(publicKey),
    's': base64UrlNoPad(secret),
    'give': displayerGives,
    'exp': expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000,
  });

  /// Reads a scanned code. Throws [HandoffException] for anything else a
  /// camera can be pointed at.
  factory HandoffInvite.decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> || json['t'] != _type) {
        throw const FormatException();
      }
      if (json['v'] != _version) {
        throw const HandoffException(
          'This code was made by a different version of ShellVibe. Update '
          'both devices and try again.',
        );
      }

      final publicKey = _bytes(json['pk'] as String);
      final secret = _bytes(json['s'] as String);
      if (publicKey.length != 32 || secret.length != 32) {
        throw const FormatException();
      }

      return HandoffInvite(
        id: json['id'] as String,
        userId: json['u'] as String,
        publicKey: publicKey,
        secret: secret,
        displayerGives: json['give'] as bool,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (json['exp'] as int) * 1000,
          isUtc: true,
        ),
      );
    } on HandoffException {
      rethrow;
    } on Object {
      throw const HandoffException('This is not a ShellVibe device code.');
    }
  }

  static Uint8List _bytes(String value) =>
      base64Url.decode(base64Url.normalize(value));
}

/// The side that shows the code.
final class HandoffDisplay {
  HandoffDisplay._(this._keyPair, this.invite);

  final SimpleKeyPair _keyPair;
  final EncryptionEngine _crypto = EncryptionEngine();
  _HandoffKeys? _keys;

  /// What goes into the QR code.
  final HandoffInvite invite;

  /// Opens the scanner's [offer] and returns what it carried: the account key
  /// when the scanner is the one giving it, otherwise nothing worth reading.
  ///
  /// Throws [HandoffException] when the offer was not made from this code --
  /// which is what a public key swapped on the way looks like.
  Future<String> acceptOffer(String offer) async {
    final Uint8List scannerPublicKey;
    final String box;
    try {
      final json = jsonDecode(offer) as Map<String, dynamic>;
      scannerPublicKey = Uint8List.fromList(
        base64.decode(json['pk'] as String),
      );
      box = json['box'] as String;
      if (scannerPublicKey.length != 32) throw const FormatException();
    } on Object {
      throw const HandoffException(_tampered);
    }

    final keys = await DeviceHandoff._keys(
      invite: invite,
      own: _keyPair,
      remote: scannerPublicKey,
      scannerPublicKey: scannerPublicKey,
    );

    final payload = await _open(_crypto, box, keys.offer);
    _keys = keys;

    return payload;
  }

  /// Seals [payload] for the scanner. Only after [acceptOffer]: until the
  /// offer has opened, there is nobody proven to be on the other end.
  Future<String> answer(String payload) {
    final keys = _keys;
    if (keys == null) {
      throw StateError('No offer has been accepted for this handoff.');
    }

    return _crypto.encrypt(plaintext: payload, secretKey: keys.answer);
  }
}

/// The side that scanned the code.
final class HandoffScan {
  HandoffScan._(this.invite, this._publicKey, this._keys);

  final HandoffInvite invite;
  final Uint8List _publicKey;
  final _HandoffKeys _keys;
  final EncryptionEngine _crypto = EncryptionEngine();

  /// The message for the mailbox's offer slot, carrying [payload].
  Future<String> offer(String payload) async => jsonEncode({
    'pk': base64.encode(_publicKey),
    'box': await _crypto.encrypt(plaintext: payload, secretKey: _keys.offer),
  });

  /// Opens the displayer's [answer].
  Future<String> openAnswer(String answer) =>
      _open(_crypto, answer, _keys.answer);
}

/// A handoff that cannot go on, with a sentence for the user.
@immutable
final class HandoffException implements Exception {
  final String message;

  const HandoffException(this.message);

  @override
  String toString() => 'HandoffException: $message';
}

final class _HandoffKeys {
  const _HandoffKeys({required this.offer, required this.answer});

  /// Two keys, one per direction, so a message cannot be played back to the
  /// side that wrote it.
  final SecretKey offer;
  final SecretKey answer;
}

const String _tampered =
    'The other device\'s reply could not be verified, so nothing was '
    'transferred. Show a new code and try again.';

Future<String> _open(EncryptionEngine crypto, String box, SecretKey key) async {
  try {
    return await crypto.decrypt(encryptedBase64: box, secretKey: key);
  } on Object {
    throw const HandoffException(_tampered);
  }
}
