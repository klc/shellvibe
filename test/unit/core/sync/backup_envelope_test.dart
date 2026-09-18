import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/core/sync/backup_envelope.dart';

/// Closes the two verification gates ADR 003 still lists as open: a tampered
/// envelope and a wrong passphrase. Both must fail closed, and neither may
/// return anything partial.
void main() {
  late BackupEnvelope envelope;
  late EncryptionEngine crypto;
  late SecretKey dek;

  const passphrase = 'correct horse battery staple';
  const payload = '{"hosts":[{"id":"h1","hostname":"example.com"}]}';

  setUp(() {
    crypto = EncryptionEngine();
    envelope = BackupEnvelope(crypto: crypto);
    dek = SecretKey(crypto.generateSalt(32));
  });

  group('seal', () {
    test('writes a v3 envelope with both wrapped keys', () async {
      final sealed = await envelope.seal(
        payloadJson: payload,
        dek: dek,
        passphrase: passphrase,
        recoveryCode: envelope.generateRecoveryCode(),
      );

      final decoded = jsonDecode(sealed) as Map<String, dynamic>;

      expect(decoded['schema_version'], 3);
      expect(decoded['salt'], isA<String>());
      expect(decoded['recovery_salt'], isA<String>());
      expect(decoded['payload'], isA<String>());
      expect(decoded['dek_wrapped'], isA<String>());
      expect(decoded['pk_wrapped_pass'], isA<String>());
      expect(decoded['pk_wrapped_recovery'], isA<String>());
    });

    test('never writes the payload or the key in the clear', () async {
      final sealed = await envelope.seal(
        payloadJson: payload,
        dek: dek,
        passphrase: passphrase,
      );

      expect(sealed, isNot(contains('example.com')));
      expect(sealed, isNot(contains('hosts')));
      expect(sealed, isNot(contains(passphrase)));
      expect(sealed, isNot(contains(base64.encode(await dek.extractBytes()))));
    });

    test('omits the recovery path when no code is given', () async {
      final sealed = await envelope.seal(
        payloadJson: payload,
        dek: dek,
        passphrase: passphrase,
      );

      final decoded = jsonDecode(sealed) as Map<String, dynamic>;

      expect(decoded['pk_wrapped_recovery'], isNull);
      expect(decoded['recovery_salt'], isNull);
      expect(BackupEnvelope.hasRecoveryPath(sealed), isFalse);
    });

    test('two seals of the same payload differ', () async {
      // Fresh payload key, fresh salts, fresh nonces. Identical output would
      // mean one of those is being reused.
      final first = await envelope.seal(
        payloadJson: payload,
        dek: dek,
        passphrase: passphrase,
      );
      final second = await envelope.seal(
        payloadJson: payload,
        dek: dek,
        passphrase: passphrase,
      );

      expect(first, isNot(second));
    });

    test('refuses an empty passphrase', () async {
      await expectLater(
        envelope.seal(payloadJson: payload, dek: dek, passphrase: ''),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });
  });

  group('open with the passphrase', () {
    test('round-trips the payload and the vault key', () async {
      final sealed = await envelope.seal(
        payloadJson: payload,
        dek: dek,
        passphrase: passphrase,
      );

      final opened = await envelope.open(
        envelopeJson: sealed,
        secret: passphrase,
      );

      expect(opened.payloadJson, payload);
      expect(opened.schemaVersion, 3);
      expect(opened.unlockedWith, BackupUnlockMethod.passphrase);
      expect(
        await opened.backupDek!.extractBytes(),
        await dek.extractBytes(),
      );
      expect(opened.isLegacyWithoutKey, isFalse);
    });

    test('a wrong passphrase fails closed', () async {
      final sealed = await envelope.seal(
        payloadJson: payload,
        dek: dek,
        passphrase: passphrase,
      );

      await expectLater(
        envelope.open(envelopeJson: sealed, secret: 'not the passphrase'),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });

    test('a passphrase differing by one character fails closed', () async {
      final sealed = await envelope.seal(
        payloadJson: payload,
        dek: dek,
        passphrase: passphrase,
      );

      await expectLater(
        envelope.open(envelopeJson: sealed, secret: '$passphrase '),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });
  });

  group('open with the recovery code', () {
    test('the recovery code opens a backup the passphrase sealed', () async {
      final code = envelope.generateRecoveryCode();
      final sealed = await envelope.seal(
        payloadJson: payload,
        dek: dek,
        passphrase: passphrase,
        recoveryCode: code,
      );

      final opened = await envelope.open(
        envelopeJson: sealed,
        secret: code,
        method: BackupUnlockMethod.recoveryCode,
      );

      expect(opened.payloadJson, payload);
      expect(opened.unlockedWith, BackupUnlockMethod.recoveryCode);
      expect(
        await opened.backupDek!.extractBytes(),
        await dek.extractBytes(),
      );
    });

    test('the passphrase still opens the same envelope', () async {
      final code = envelope.generateRecoveryCode();
      final sealed = await envelope.seal(
        payloadJson: payload,
        dek: dek,
        passphrase: passphrase,
        recoveryCode: code,
      );

      final opened = await envelope.open(
        envelopeJson: sealed,
        secret: passphrase,
      );

      expect(opened.payloadJson, payload);
    });

    test('grouping, case and spacing do not change the key', () async {
      // A code pasted from a password manager arrives without the dashes. If
      // that derived a different key the user would be told their correct code
      // is wrong.
      final code = envelope.generateRecoveryCode();
      final sealed = await envelope.seal(
        payloadJson: payload,
        dek: dek,
        passphrase: passphrase,
        recoveryCode: code,
      );

      for (final variant in [
        code.replaceAll('-', ''),
        code.toLowerCase(),
        code.replaceAll('-', ' '),
        '  $code  ',
      ]) {
        final opened = await envelope.open(
          envelopeJson: sealed,
          secret: variant,
          method: BackupUnlockMethod.recoveryCode,
        );

        expect(opened.payloadJson, payload, reason: 'variant: $variant');
      }
    });

    test('a wrong recovery code fails closed', () async {
      final sealed = await envelope.seal(
        payloadJson: payload,
        dek: dek,
        passphrase: passphrase,
        recoveryCode: envelope.generateRecoveryCode(),
      );

      await expectLater(
        envelope.open(
          envelopeJson: sealed,
          secret: envelope.generateRecoveryCode(),
          method: BackupUnlockMethod.recoveryCode,
        ),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });

    test('asking for recovery on a backup without one fails clearly', () async {
      final sealed = await envelope.seal(
        payloadJson: payload,
        dek: dek,
        passphrase: passphrase,
      );

      await expectLater(
        envelope.open(
          envelopeJson: sealed,
          secret: 'anything',
          method: BackupUnlockMethod.recoveryCode,
        ),
        throwsA(
          isA<BackupEnvelopeException>().having(
            (e) => e.reason,
            'reason',
            contains('no recovery code'),
          ),
        ),
      );
    });

    test('hasRecoveryPath reports the truth without opening', () async {
      final withCode = await envelope.seal(
        payloadJson: payload,
        dek: dek,
        passphrase: passphrase,
        recoveryCode: envelope.generateRecoveryCode(),
      );

      expect(BackupEnvelope.hasRecoveryPath(withCode), isTrue);
      expect(BackupEnvelope.hasRecoveryPath('not json'), isFalse);
    });

    test('generated codes are distinct and use the safe alphabet', () {
      final codes = {for (var i = 0; i < 25; i++) envelope.generateRecoveryCode()};

      expect(codes, hasLength(25));

      for (final code in codes) {
        final normalized = BackupEnvelope.normalizeRecoveryCode(code);

        expect(normalized, hasLength(BackupEnvelope.recoveryCodeBytes));
        expect(
          normalized,
          matches(RegExp(r'^[0-9ABCDEFGHJKMNPQRSTVWXYZ]+$')),
          reason: 'I, L, O and U are excluded so a handwritten code cannot be '
              'misread.',
        );
      }
    });
  });

  group('tampering', () {
    Future<String> sealed() => envelope.seal(
      payloadJson: payload,
      dek: dek,
      passphrase: passphrase,
      recoveryCode: 'RECOVERY-CODE-FOR-THE-TAMPER-TEST',
    );

    /// Flips one base64 character of [field], which flips ciphertext bits.
    String corrupt(String envelopeJson, String field) {
      final decoded = jsonDecode(envelopeJson) as Map<String, dynamic>;
      final value = decoded[field] as String;
      final index = value.length ~/ 2;
      final replacement = value[index] == 'A' ? 'B' : 'A';

      decoded[field] =
          value.substring(0, index) + replacement + value.substring(index + 1);

      return jsonEncode(decoded);
    }

    test('a flipped payload byte is refused, not partially decoded', () async {
      await expectLater(
        envelope.open(
          envelopeJson: corrupt(await sealed(), 'payload'),
          secret: passphrase,
        ),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });

    test('a flipped wrapped-key byte is refused', () async {
      await expectLater(
        envelope.open(
          envelopeJson: corrupt(await sealed(), 'pk_wrapped_pass'),
          secret: passphrase,
        ),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });

    test('a flipped wrapped-DEK byte is refused', () async {
      await expectLater(
        envelope.open(
          envelopeJson: corrupt(await sealed(), 'dek_wrapped'),
          secret: passphrase,
        ),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });

    test('a swapped salt is refused', () async {
      final original = jsonDecode(await sealed()) as Map<String, dynamic>;
      original['salt'] = base64.encode(crypto.generateSalt());

      await expectLater(
        envelope.open(
          envelopeJson: jsonEncode(original),
          secret: passphrase,
        ),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });

    test(
      'a payload lifted from another backup is refused under this one',
      () async {
        // Cut-and-paste across envelopes: each has its own payload key, so the
        // borrowed ciphertext cannot authenticate here.
        final mine = jsonDecode(await sealed()) as Map<String, dynamic>;
        final theirs =
            jsonDecode(
                  await envelope.seal(
                    payloadJson: '{"hosts":[{"id":"evil"}]}',
                    dek: dek,
                    passphrase: 'a different passphrase',
                  ),
                )
                as Map<String, dynamic>;

        mine['payload'] = theirs['payload'];

        await expectLater(
          envelope.open(envelopeJson: jsonEncode(mine), secret: passphrase),
          throwsA(isA<BackupEnvelopeException>()),
        );
      },
    );
  });

  group('malformed and unsupported envelopes', () {
    test('a non-JSON file is refused', () async {
      await expectLater(
        envelope.open(envelopeJson: 'this is not json', secret: passphrase),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });

    test('a JSON array is refused', () async {
      await expectLater(
        envelope.open(envelopeJson: '[1,2,3]', secret: passphrase),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });

    test('an envelope missing its fields is refused', () async {
      await expectLater(
        envelope.open(
          envelopeJson: '{"schema_version":3}',
          secret: passphrase,
        ),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });

    test('a future version says so rather than failing obscurely', () async {
      await expectLater(
        envelope.open(
          envelopeJson: '{"schema_version":99}',
          secret: passphrase,
        ),
        throwsA(
          isA<BackupEnvelopeException>().having(
            (e) => e.reason,
            'reason',
            contains('newer version'),
          ),
        ),
      );
    });
  });

  group('backward compatibility', () {
    /// Builds a v2 envelope the way the previous release wrote them: payload
    /// and DEK encrypted directly under the passphrase key, no payload key.
    Future<String> sealV2() async {
      final salt = crypto.generateSalt();
      final key = await crypto.deriveMasterKeyInBackground(
        masterPassword: passphrase,
        salt: salt,
      );

      return jsonEncode({
        'schema_version': 2,
        'salt': base64.encode(salt),
        'payload': await crypto.encrypt(plaintext: payload, secretKey: key),
        'dek_wrapped': await crypto.encrypt(
          plaintext: base64.encode(await dek.extractBytes()),
          secretKey: key,
        ),
      });
    }

    test('a v2 envelope still opens with its vault key', () async {
      final opened = await envelope.open(
        envelopeJson: await sealV2(),
        secret: passphrase,
      );

      expect(opened.payloadJson, payload);
      expect(opened.schemaVersion, 2);
      expect(opened.isLegacyWithoutKey, isFalse);
      expect(
        await opened.backupDek!.extractBytes(),
        await dek.extractBytes(),
      );
    });

    test('a v2 envelope with a wrong passphrase fails closed', () async {
      await expectLater(
        envelope.open(envelopeJson: await sealV2(), secret: 'wrong'),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });

    test('a v1 envelope opens and reports that it carries no key', () async {
      final salt = crypto.generateSalt();
      final key = await crypto.deriveMasterKeyInBackground(
        masterPassword: passphrase,
        salt: salt,
      );
      final v1 = jsonEncode({
        'schema_version': 1,
        'salt': base64.encode(salt),
        'payload': await crypto.encrypt(plaintext: payload, secretKey: key),
      });

      final opened = await envelope.open(envelopeJson: v1, secret: passphrase);

      expect(opened.payloadJson, payload);
      expect(opened.schemaVersion, 1);
      expect(
        opened.isLegacyWithoutKey,
        isTrue,
        reason: 'A v1 backup cannot decrypt its own secrets elsewhere.',
      );
    });

    test('a v2 envelope missing its wrapped key is refused', () async {
      final salt = crypto.generateSalt();
      final key = await crypto.deriveMasterKeyInBackground(
        masterPassword: passphrase,
        salt: salt,
      );

      await expectLater(
        envelope.open(
          envelopeJson: jsonEncode({
            'schema_version': 2,
            'salt': base64.encode(salt),
            'payload': await crypto.encrypt(
              plaintext: payload,
              secretKey: key,
            ),
          }),
          secret: passphrase,
        ),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });
  });
}
