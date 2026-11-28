import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_client.dart';
import 'package:shellvibe/core/sync/account_key.dart';
import 'package:shellvibe/core/sync/backup_envelope.dart';
import 'package:shellvibe/features/cloud_backup/data/account_key_api.dart';
import 'package:shellvibe/features/cloud_backup/data/cloud_backup_store.dart';
import 'package:shellvibe/features/cloud_backup/domain/account_key_service.dart';

import '../../../support/cloud_backup_store.dart';
import '../../../support/fake_sync_server.dart';
import '../../../support/fast_crypto.dart';

/// How the account key reaches a device, and what stops a wrong one staying.
///
/// The failure this guards against is the one the sync key already had: two
/// devices each minting a key and carrying on, with nothing failing and
/// neither able to read the other.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSyncServer server;
  late AccountKeyRecord records;

  const passphrase = 'a long enough passphrase';
  const recoveryCode = 'X4K7M-9PQR2-ABCDE-FGHJK-MNPQR-STVWX-YZ';

  CloudBackupStore store() => testCloudBackupStore();

  AccountKeyService service({AccountKeyTransport? api}) => AccountKeyService(
    store: store(),
    api:
        api ??
        AccountKeyApi(
          client: ApiClient(
            transport: server,
            tokenProvider: () async => 'test-token',
          ),
        ),
    deviceId: 'device-a',
    records: records,
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    server = FakeSyncServer()..accountKeyEnabled = true;
    records = AccountKeyRecord(crypto: fastEncryptionEngine());
  });

  /// The record another device would have written, and its key.
  Future<AccountKey> seededByAnotherDevice({
    String passphrase = passphrase,
    String? recoveryCode,
  }) async {
    final key = records.generateKey();
    server
      ..accountKeyRecord = await records.build(
        accountKey: key,
        passphrase: passphrase,
        recoveryCode: recoveryCode,
      )
      ..accountKeyRevision = 1;

    return AccountKey(bytes: key, record: server.accountKeyRecord!);
  }

  group('first-time setup', () {
    test('gives the account a key both secrets open', () async {
      expect(
        await service().create(
          passphrase: passphrase,
          recoveryCode: recoveryCode,
        ),
        AccountKeyOutcome.ready,
      );

      final key = await store().readAccountKey();
      expect(key, isNotNull);
      expect(
        await records.open(
          recordJson: server.accountKeyRecord!,
          secret: passphrase,
        ),
        key,
      );
      expect(
        await records.open(
          recordJson: server.accountKeyRecord!,
          secret: recoveryCode,
          method: BackupUnlockMethod.recoveryCode,
        ),
        key,
      );
    });

    test('waits while the server is not handing keys out', () async {
      server.accountKeyEnabled = false;

      expect(
        await service().create(
          passphrase: passphrase,
          recoveryCode: recoveryCode,
        ),
        AccountKeyOutcome.notYet,
      );
      expect(await store().readAccountKey(), isNull);
      expect(server.accountKeyRecord, isNull);
    });

    test('a server from before the key existed counts as not yet', () async {
      server.intercept = (request) =>
          request.url.path.endsWith('/sync/account-key')
          ? FakeSyncServer.error(404, 'not_found', 'No such route.')
          : null;

      expect(await service().migrate(), AccountKeyOutcome.notYet);
    });

    test('does not replace a key the account already has', () async {
      final existing = await seededByAnotherDevice();

      expect(
        await service().create(
          passphrase: 'a different passphrase',
          recoveryCode: recoveryCode,
        ),
        AccountKeyOutcome.alreadyExists,
      );
      expect(server.accountKeyRecord, existing.record);
      expect(await store().readAccountKey(), isNull);
    });
  });

  group('a device that still seals with the passphrase', () {
    setUp(() async {
      await store().writePassphrase(passphrase);
      await store().writeRecoveryCode(recoveryCode);
    });

    test('moves to a key of its own making when there is none', () async {
      expect(await service().migrate(), AccountKeyOutcome.ready);

      expect(await store().readAccountKey(), isNotNull);
      expect(
        AccountKeyRecord.hasRecoverySlot(server.accountKeyRecord!),
        isTrue,
      );
      // The passphrase is dropped later, by the caller, once nothing needs it.
      expect(await store().readPassphrase(), passphrase);
    });

    test('adopts the key another device made first', () async {
      final theirs = await seededByAnotherDevice();

      expect(await service().migrate(), AccountKeyOutcome.ready);
      expect(await store().readAccountKey(), theirs.bytes);
    });

    test('two devices moving at once end with one key', () async {
      // This device reads "no record", and the other one writes before it
      // does. Without the revision check both would keep the key they made.
      late AccountKey theirs;
      final api = _RacingTransport(
        AccountKeyApi(
          client: ApiClient(
            transport: server,
            tokenProvider: () async => 'test-token',
          ),
        ),
        // With the recovery code, so this device has nothing to add to it.
        afterFirstRead: () async =>
            theirs = await seededByAnotherDevice(recoveryCode: recoveryCode),
      );

      expect(await service(api: api).migrate(), AccountKeyOutcome.ready);

      expect(await store().readAccountKey(), theirs.bytes);
      expect(server.accountKeyRevision, 1, reason: 'the loser wrote nothing');
    });

    test('fills in a recovery code the first device did not know', () async {
      await seededByAnotherDevice();
      expect(
        AccountKeyRecord.hasRecoverySlot(server.accountKeyRecord!),
        isFalse,
      );

      expect(await service().migrate(), AccountKeyOutcome.ready);

      expect(
        await records.open(
          recordJson: server.accountKeyRecord!,
          secret: recoveryCode,
          method: BackupUnlockMethod.recoveryCode,
        ),
        await store().readAccountKey(),
      );
    });

    test('keeps nothing when its passphrase is not the account\'s', () async {
      await seededByAnotherDevice(passphrase: 'what the other devices use');

      expect(await service().migrate(), AccountKeyOutcome.wrongSecret);
      expect(await store().readAccountKey(), isNull);
    });
  });

  group('joining an account that has a key', () {
    test('with the passphrase, or with the recovery code alone', () async {
      final theirs = await seededByAnotherDevice(recoveryCode: recoveryCode);

      expect(
        await service().unlock(
          secret: recoveryCode,
          method: BackupUnlockMethod.recoveryCode,
        ),
        AccountKeyOutcome.ready,
      );
      expect(await store().readAccountKey(), theirs.bytes);

      await store().clear();
      expect(
        await service().unlock(secret: passphrase),
        AccountKeyOutcome.ready,
      );
      expect(await store().readAccountKey(), theirs.bytes);

      // Either way, neither secret stays on the device.
      expect(await store().hasPassphrase(), isFalse);
      expect(await store().hasRecoveryCode(), isFalse);
    });

    test('a wrong secret stores nothing', () async {
      await seededByAnotherDevice();

      expect(
        await service().unlock(secret: 'not the passphrase'),
        AccountKeyOutcome.wrongSecret,
      );
      expect(await store().isConfigured(), isFalse);
    });

    test('a key handed over is kept only if it is this account\'s', () async {
      final theirs = await seededByAnotherDevice();

      expect(
        await service().adopt(records.generateKey()),
        AccountKeyOutcome.wrongSecret,
      );
      expect(await store().isConfigured(), isFalse);

      expect(await service().adopt(theirs.bytes), AccountKeyOutcome.ready);
      expect(await store().readAccountKey(), theirs.bytes);
    });
  });

  group('a device that holds the key', () {
    test('reads the record as the account has it now', () async {
      final theirs = await seededByAnotherDevice();
      await store().writeAccountKey(theirs.bytes);

      // Another device adds a recovery code after this one joined.
      server.accountKeyRecord = await records.withRecoveryCode(
        recordJson: theirs.record,
        accountKey: theirs.bytes,
        recoveryCode: recoveryCode,
      );

      final current = await service().current();
      expect(AccountKeyRecord.hasRecoverySlot(current!.record), isTrue);
    });

    test('refuses a record that is not its key\'s', () async {
      await store().writeAccountKey(records.generateKey());
      await seededByAnotherDevice();

      await expectLater(
        service().current(),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });

    test('adds a recovery code without the passphrase', () async {
      final theirs = await seededByAnotherDevice();
      await store().writeAccountKey(theirs.bytes);
      expect(await service().hasRecoveryCode(), isFalse);

      await service().setRecoveryCode(recoveryCode);

      expect(await service().hasRecoveryCode(), isTrue);
      expect(
        await records.open(
          recordJson: server.accountKeyRecord!,
          secret: passphrase,
        ),
        theirs.bytes,
        reason: 'the passphrase slot is carried over',
      );
    });
  });
}

/// Lets something happen on the server between this device's first read and
/// whatever it does next.
final class _RacingTransport implements AccountKeyTransport {
  _RacingTransport(this._inner, {required this.afterFirstRead});

  final AccountKeyTransport _inner;
  final Future<void> Function() afterFirstRead;
  bool _raced = false;

  @override
  Future<AccountKeyHead> read() async {
    final head = await _inner.read();
    if (!_raced) {
      _raced = true;
      await afterFirstRead();
    }

    return head;
  }

  @override
  Future<AccountKeyHead> write({
    required int baseRevision,
    required String record,
    required String deviceId,
  }) => _inner.write(
    baseRevision: baseRevision,
    record: record,
    deviceId: deviceId,
  );
}
