import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/backup_envelope.dart';

/// The sync key is the reason v4 exists.
///
/// It is random and lives as long as the vault, rather than being derived from
/// the passphrase. Deriving it would mean a passphrase change made every
/// operation already in the log unreadable -- so the passphrase could either
/// never change, or the whole log would have to be rewritten. Wrapping it
/// instead means a passphrase change rewraps 32 bytes.
void main() {
  late BackupEnvelope envelope;

  const passphrase = 'envelope v4 passphrase';

  setUp(() => envelope = BackupEnvelope());

  Future<SecretKey> dek() async => SecretKey(envelope.generateSyncKey());

  test('an envelope without a sync key stays at v3', () async {
    // A v4 envelope is refused outright by a build that reads up to v3, so
    // one is only written when it holds something a v3 cannot.
    final sealed = await envelope.seal(
      payloadJson: '{}',
      dek: await dek(),
      passphrase: passphrase,
    );

    final opened = await envelope.open(
      envelopeJson: sealed,
      secret: passphrase,
    );

    expect(opened.schemaVersion, kBackupSchemaVersionWithoutSyncKey);
    expect(opened.syncKey, isNull);
  });

  test('a sync key makes it a v4 and comes back intact', () async {
    final syncKey = envelope.generateSyncKey();

    final opened = await envelope.open(
      envelopeJson: await envelope.seal(
        payloadJson: '{"hello":"world"}',
        dek: await dek(),
        passphrase: passphrase,
        syncKey: syncKey,
      ),
      secret: passphrase,
    );

    expect(opened.schemaVersion, kBackupSchemaVersion);
    expect(await opened.syncKey!.extractBytes(), syncKey);
    expect(opened.payloadJson, '{"hello":"world"}');
  });

  test('the recovery code reaches the sync key too', () async {
    // It is wrapped under the payload key, not under each secret in turn, so
    // every path that opens the envelope at all reaches it.
    final syncKey = envelope.generateSyncKey();
    final code = envelope.generateRecoveryCode();

    final sealed = await envelope.seal(
      payloadJson: '{}',
      dek: await dek(),
      passphrase: passphrase,
      recoveryCode: code,
      syncKey: syncKey,
    );

    final opened = await envelope.open(
      envelopeJson: sealed,
      secret: code,
      method: BackupUnlockMethod.recoveryCode,
    );

    expect(await opened.syncKey!.extractBytes(), syncKey);
  });

  test('changing the passphrase keeps the same sync key', () async {
    // The property the whole design turns on: the operation log stays
    // readable across a passphrase change.
    final syncKey = envelope.generateSyncKey();
    final vaultDek = await dek();

    final first = await envelope.open(
      envelopeJson: await envelope.seal(
        payloadJson: '{}',
        dek: vaultDek,
        passphrase: 'old passphrase',
        syncKey: syncKey,
      ),
      secret: 'old passphrase',
    );

    final second = await envelope.open(
      envelopeJson: await envelope.seal(
        payloadJson: '{}',
        dek: vaultDek,
        passphrase: 'new passphrase',
        syncKey: Uint8List.fromList(await first.syncKey!.extractBytes()),
      ),
      secret: 'new passphrase',
    );

    expect(await second.syncKey!.extractBytes(), syncKey);
  });

  test('a v4 envelope does not open with the wrong passphrase', () async {
    final sealed = await envelope.seal(
      payloadJson: '{}',
      dek: await dek(),
      passphrase: passphrase,
      syncKey: envelope.generateSyncKey(),
    );

    await expectLater(
      envelope.open(envelopeJson: sealed, secret: 'not it'),
      throwsA(isA<BackupEnvelopeException>()),
    );
  });

  test('two sync keys are not the same key', () {
    expect(envelope.generateSyncKey(), isNot(envelope.generateSyncKey()));
  });
}
