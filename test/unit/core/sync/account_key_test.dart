import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/account_key.dart';
import 'package:shellvibe/core/sync/backup_envelope.dart';

import '../../../support/fast_crypto.dart';

/// The account key is the reason v5 exists.
///
/// A device holds a random key and seals with that; the passphrase and the
/// recovery code only wrap it. So a device joins without anybody typing the
/// passphrase into it, and neither secret has to be kept on any device.
void main() {
  late AccountKeyRecord records;
  late BackupEnvelope envelope;

  const passphrase = 'account key passphrase';
  const recoveryCode = 'X4K7M-9PQR2-ABCDE-FGHJK-MNPQR-STVWX-YZ';

  setUp(() {
    records = AccountKeyRecord(crypto: fastEncryptionEngine());
    envelope = BackupEnvelope(crypto: fastEncryptionEngine());
  });

  SecretKey dek() => SecretKey(envelope.generateSyncKey());

  group('the key record', () {
    test('the passphrase and the recovery code reach the same key', () async {
      final key = records.generateKey();
      final record = await records.build(
        accountKey: key,
        passphrase: passphrase,
        recoveryCode: recoveryCode,
      );

      expect(await records.open(recordJson: record, secret: passphrase), key);
      expect(
        await records.open(
          recordJson: record,
          // As a password manager pastes it: no dashes, lower case.
          secret: recoveryCode.replaceAll('-', '').toLowerCase(),
          method: BackupUnlockMethod.recoveryCode,
        ),
        key,
      );
    });

    test('a wrong secret opens nothing', () async {
      final record = await records.build(
        accountKey: records.generateKey(),
        passphrase: passphrase,
      );

      await expectLater(
        records.open(recordJson: record, secret: 'not the passphrase'),
        throwsA(isA<BackupEnvelopeException>()),
      );
      await expectLater(
        records.open(
          recordJson: record,
          secret: recoveryCode,
          method: BackupUnlockMethod.recoveryCode,
        ),
        throwsA(isA<BackupEnvelopeException>()),
        reason: 'it was built without a recovery slot',
      );
    });

    test('a key holder can tell its record from another', () async {
      final key = records.generateKey();
      final record = await records.build(
        accountKey: key,
        passphrase: passphrase,
      );

      expect(await records.belongsTo(record, key), isTrue);
      expect(await records.belongsTo(record, records.generateKey()), isFalse);
      expect(await records.belongsTo('not json', key), isFalse);
    });

    test('a slot moved into another record is refused', () async {
      // What a server that wanted a passphrase of its own choosing to open
      // the account would try: a slot it built, dropped into the real record.
      final key = records.generateKey();
      final real =
          jsonDecode(
                await records.build(accountKey: key, passphrase: passphrase),
              )
              as Map<String, dynamic>;
      final forged =
          jsonDecode(
                await records.build(
                  accountKey: records.generateKey(),
                  passphrase: 'the server\'s own passphrase',
                ),
              )
              as Map<String, dynamic>;

      final spliced = jsonEncode({...real, 'body': forged['body']});

      expect(await records.belongsTo(spliced, key), isFalse);
      await expectLater(
        records.open(
          recordJson: spliced,
          secret: 'the server\'s own passphrase',
        ),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });

    test('a recovery code is added with the key alone', () async {
      // A device that joined by code never knew the passphrase, and it is
      // still able to give the account a recovery path.
      final key = records.generateKey();
      final before = await records.build(
        accountKey: key,
        passphrase: passphrase,
      );
      expect(AccountKeyRecord.hasRecoverySlot(before), isFalse);

      final after = await records.withRecoveryCode(
        recordJson: before,
        accountKey: key,
        recoveryCode: recoveryCode,
      );

      expect(AccountKeyRecord.hasRecoverySlot(after), isTrue);
      expect(await records.belongsTo(after, key), isTrue);
      expect(await records.open(recordJson: after, secret: passphrase), key);
      expect(
        await records.open(
          recordJson: after,
          secret: recoveryCode,
          method: BackupUnlockMethod.recoveryCode,
        ),
        key,
      );

      await expectLater(
        records.withRecoveryCode(
          recordJson: before,
          accountKey: records.generateKey(),
          recoveryCode: recoveryCode,
        ),
        throwsA(isA<BackupEnvelopeException>()),
        reason: 'a device cannot sign a record that is not its own',
      );
    });
  });

  group('a v5 envelope', () {
    late Uint8List key;
    late String record;
    late String sealed;
    late Uint8List syncKey;

    setUp(() async {
      key = records.generateKey();
      record = await records.build(
        accountKey: key,
        passphrase: passphrase,
        recoveryCode: recoveryCode,
      );
      syncKey = envelope.generateSyncKey();
      sealed = await envelope.sealWithAccountKey(
        payloadJson: '{"hello":"world"}',
        dek: dek(),
        accountKey: key,
        keyRecord: record,
        syncKey: syncKey,
      );
    });

    test('opens with the account key, no secret typed', () async {
      final opened = await envelope.open(envelopeJson: sealed, accountKey: key);

      expect(opened.schemaVersion, kBackupSchemaVersionAccountKey);
      expect(opened.unlockedWith, BackupUnlockMethod.accountKey);
      expect(opened.payloadJson, '{"hello":"world"}');
      expect(await opened.syncKey!.extractBytes(), syncKey);
    });

    test('still opens with the passphrase or the recovery code', () async {
      // On its own, with no server to ask: the record travels inside.
      final byPassphrase = await envelope.open(
        envelopeJson: sealed,
        secret: passphrase,
      );
      final byCode = await envelope.open(
        envelopeJson: sealed,
        secret: recoveryCode,
        method: BackupUnlockMethod.recoveryCode,
      );

      expect(byPassphrase.payloadJson, '{"hello":"world"}');
      expect(byPassphrase.accountKey, key);
      expect(byCode.accountKey, key);
      expect(BackupEnvelope.hasRecoveryPath(sealed), isTrue);
    });

    test('does not open with another account\'s key', () async {
      await expectLater(
        envelope.open(envelopeJson: sealed, accountKey: records.generateKey()),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });

    test(
      'a device with only the key says why an older one stays shut',
      () async {
        final v4 = await envelope.seal(
          payloadJson: '{}',
          dek: dek(),
          passphrase: passphrase,
          syncKey: syncKey,
        );

        await expectLater(
          envelope.open(envelopeJson: v4, accountKey: key),
          throwsA(
            isA<BackupEnvelopeException>().having(
              (e) => e.reason,
              'reason',
              contains('before the account key existed'),
            ),
          ),
        );

        // With the passphrase beside the key, as on a device still migrating.
        final opened = await envelope.open(
          envelopeJson: v4,
          secret: passphrase,
          accountKey: key,
        );
        expect(opened.schemaVersion, kBackupSchemaVersion);
      },
    );
  });
}
