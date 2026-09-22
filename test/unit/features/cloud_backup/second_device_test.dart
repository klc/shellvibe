import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_client.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/core/sync/e2ee_cloud_sync_service.dart';
import 'package:shellvibe/features/cloud_backup/data/cloud_backup_api.dart';
import 'package:shellvibe/features/cloud_backup/data/cloud_backup_store.dart';
import 'package:shellvibe/features/cloud_backup/domain/cloud_backup_service.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

import '../../../support/fake_api_transport.dart';

/// The second-device bug, and the recovery-code bug beside it.
///
/// A phone signing in to an account that already had a desktop backup was
/// offered first-time setup, invented a *new* passphrase, and immediately
/// uploaded its empty database over the good revision. The desktop's backup
/// then could not be opened from the phone, because it was sealed with a
/// different secret.
///
/// Reported from real use, not caught by any test here, because every test
/// only ever exercised one device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeApiTransport transport;
  late CloudBackupService service;
  late AppDatabase db;

  const deviceId = '01PHONE000000000000000000';
  const desktopPassphrase = 'the passphrase set on the desktop';

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    transport = FakeApiTransport();
    db = AppDatabase(NativeDatabase.memory());

    final vaultKeyService = VaultKeyService(
      encryptionEngine: EncryptionEngine(),
      secureStorageService: SecureStorageService(),
    );
    await vaultKeyService.getDek();

    service = CloudBackupService(
      api: CloudBackupApi(
        client: ApiClient(
          transport: transport,
          tokenProvider: () async => 'test-token',
        ),
      ),
      sync: E2EECloudSyncService(vaultKeyService: vaultKeyService),
      readPendingUploadId: () async => null,
      writePendingUploadId: (_) async {},
      newUploadId: () => 'upload-1',
    );
  });

  tearDown(() => db.close());

  /// An envelope as the desktop would have sealed it.
  Future<String> desktopEnvelope({String? recoveryCode}) async {
    final crypto = EncryptionEngine();

    return BackupEnvelope(crypto: crypto).seal(
      payloadJson: jsonEncode({
        'version': 1,
        'hosts': [
          {'id': 'h1', 'label': 'prod', 'hostname': '10.0.0.1', 'port': 22},
        ],
      }),
      dek: SecretKey(crypto.generateSalt(32)),
      passphrase: desktopPassphrase,
      recoveryCode: recoveryCode,
    );
  }

  void enqueueHead({required int revision}) {
    transport.enqueue(
      body: {
        'data': {
          'id': '01VAULT0000000000000000000',
          'current_revision': revision,
          'current_hash': revision == 0 ? null : 'abc',
          'bytes_used': 0,
        },
      },
    );
  }

  void enqueueRevision(String ciphertext, {int revision = 1}) {
    transport.enqueue(
      body: {
        'data': {
          'id': '01REV00000000000000000000',
          'revision': revision,
          'base_revision': revision - 1,
          'device_id': '01DESKTOP0000000000000000',
          'schema_version': kBackupSchemaVersion,
          'encryption_version': kEncryptionVersion,
          'ciphertext_sha256': '',
          'size_bytes': ciphertext.length,
          'ciphertext': ciphertext,
        },
      },
    );
  }

  group('a device joining an account that already has a backup', () {
    test('the existing passphrase opens the stored revision', () async {
      final envelope = await desktopEnvelope();
      enqueueRevision(envelope);

      expect(
        await service.canOpen(revision: 1, secret: desktopPassphrase),
        isNotNull,
      );
    });

    test('a newly invented passphrase does not', () async {
      // This is the bug in one line: the phone made up its own secret, so the
      // desktop's backup was unopenable there.
      final envelope = await desktopEnvelope();
      enqueueRevision(envelope);

      expect(
        await service.canOpen(revision: 1, secret: 'a new phone passphrase'),
        isNull,
      );
    });

    test('verifying writes nothing to the database', () async {
      final envelope = await desktopEnvelope();
      enqueueRevision(envelope);

      final before = (await db.select(db.workspaces).get()).length;

      await service.canOpen(revision: 1, secret: desktopPassphrase);

      expect(
        (await db.select(db.workspaces).get()).length,
        before,
        reason: 'Checking a passphrase must not restore anything.',
      );
    });

    test('the recovery code also proves ownership', () async {
      const code = 'ABCDE-FGHJK-MNPQR-STVWX';
      final envelope = await desktopEnvelope(recoveryCode: code);
      enqueueRevision(envelope);

      expect(
        await service.canOpen(
          revision: 1,
          secret: code,
          unlockWith: BackupUnlockMethod.recoveryCode,
        ),
        isNotNull,
      );
    });

    test('a revision with no ciphertext cannot be verified', () async {
      transport.enqueue(
        body: {
          'data': {'revision': 1, 'ciphertext_sha256': ''},
        },
      );

      expect(
        await service.canOpen(revision: 1, secret: desktopPassphrase),
        isNull,
      );
    });

    test('the head tells a joining device the account is not empty', () async {
      // What `build()` now asks before deciding between setup and unlock.
      enqueueHead(revision: 4);

      final head = await service.head();

      expect(head.isEmpty, isFalse);
      expect(head.currentRevision, 4);
    });

    test('an empty head is a genuine first-time setup', () async {
      enqueueHead(revision: 0);

      expect((await service.head()).isEmpty, isTrue);
    });
  });

  group('the recovery code survives past the first backup', () {
    test('the store keeps it so later uploads can seal it in', () async {
      // It used to be passed to `configure()` and dropped, so only the very
      // first backup carried a recovery path and every later one silently did
      // not.
      final store = CloudBackupStore(storage: SecureStorageService());

      expect(await store.readRecoveryCode(), isNull);

      await store.writeRecoveryCode('ABCDE-FGHJK');

      expect(await store.readRecoveryCode(), 'ABCDE-FGHJK');
    });

    test('clearing the device forgets it with everything else', () async {
      final store = CloudBackupStore(storage: SecureStorageService());

      await store.writePassphrase('p');
      await store.writeRecoveryCode('ABCDE-FGHJK');
      await store.clear();

      expect(await store.readRecoveryCode(), isNull);
      expect(await store.readPassphrase(), isNull);
    });

    test('a backup sealed with a stored code opens with that code', () async {
      const code = 'ABCDE-FGHJK-MNPQR-STVWX';

      enqueueHead(revision: 0);
      transport.enqueue(
        status: 201,
        body: {
          'data': {
            'id': '01REV00000000000000000000',
            'revision': 1,
            'base_revision': 0,
            'device_id': deviceId,
            'schema_version': kBackupSchemaVersion,
            'encryption_version': kEncryptionVersion,
            'ciphertext_sha256': '',
            'size_bytes': 1,
          },
        },
      );

      final result = await service.upload(
        db: db,
        passphrase: 'device passphrase',
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
        recoveryCode: code,
      );

      expect(result.succeeded, isTrue);

      final sealed = transport.lastBody['ciphertext']! as String;

      expect(
        BackupEnvelope.hasRecoveryPath(sealed),
        isTrue,
        reason: 'An upload given a recovery code must seal one in.',
      );
    });

    test('a backup sealed without one has no recovery path', () async {
      enqueueHead(revision: 0);
      transport.enqueue(
        status: 201,
        body: {
          'data': {
            'revision': 1,
            'base_revision': 0,
            'device_id': deviceId,
            'schema_version': kBackupSchemaVersion,
            'encryption_version': kEncryptionVersion,
            'ciphertext_sha256': '',
            'size_bytes': 1,
          },
        },
      );

      await service.upload(
        db: db,
        passphrase: 'device passphrase',
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
      );

      expect(
        BackupEnvelope.hasRecoveryPath(
          transport.lastBody['ciphertext']! as String,
        ),
        isFalse,
        reason:
            'Which is why the UI has to say so rather than let the user '
            'believe the code covers this backup.',
      );
    });
  });
}
