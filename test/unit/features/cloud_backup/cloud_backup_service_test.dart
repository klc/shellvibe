import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_client.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/core/sync/e2ee_cloud_sync_service.dart';
import 'package:shellvibe/features/cloud_backup/data/cloud_backup_api.dart';
import 'package:shellvibe/features/cloud_backup/domain/cloud_backup_service.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

import '../../../support/contract_fixture.dart';
import '../../../support/fake_api_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeApiTransport transport;
  late AppDatabase db;
  late CloudBackupService service;
  late String? pendingUploadId;
  late int uploadIdCounter;

  const deviceId = '01DEVICEULID00000000000000';
  const passphrase = 'a sync passphrase';

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});

    transport = FakeApiTransport();
    db = AppDatabase(NativeDatabase.memory());

    final vaultKeyService = VaultKeyService(
      encryptionEngine: EncryptionEngine(),
      secureStorageService: SecureStorageService(),
    );
    // An unconfigured vault hands out a plaintext DEK, which is what a device
    // with no master password set has.
    await vaultKeyService.getDek();

    pendingUploadId = null;
    uploadIdCounter = 0;

    service = CloudBackupService(
      api: CloudBackupApi(
        client: ApiClient(
          transport: transport,
          tokenProvider: () async => 'test-token',
        ),
      ),
      sync: E2EECloudSyncService(vaultKeyService: vaultKeyService),
      readPendingUploadId: () async => pendingUploadId,
      writePendingUploadId: (id) async => pendingUploadId = id,
      newUploadId: () => 'upload-${++uploadIdCounter}',
    );
  });

  tearDown(() => db.close());

  void enqueueHead({int currentRevision = 0}) {
    transport.enqueue(
      body: {
        'data': {
          'id': '01VAULT0000000000000000000',
          'current_revision': currentRevision,
          'current_hash': currentRevision == 0 ? null : 'abc',
          'bytes_used': 0,
          'updated_at': '2026-09-18T10:00:00Z',
        },
      },
    );
  }

  void enqueueUploadAccepted({int revision = 1}) {
    transport.enqueue(
      status: 201,
      body: {
        'data': {
          'id': '01REV00000000000000000000',
          'vault_id': '01VAULT0000000000000000000',
          'revision': revision,
          'base_revision': revision - 1,
          'device_id': deviceId,
          'upload_id': 'upload-1',
          'schema_version': kBackupSchemaVersion,
          'encryption_version': kEncryptionVersion,
          'ciphertext_sha256': 'x' * 64,
          'size_bytes': 42,
          'created_at': '2026-09-18T10:00:00Z',
        },
      },
    );
  }

  group('upload', () {
    test('sends an opaque envelope and the checksum of its bytes', () async {
      enqueueHead();
      enqueueUploadAccepted();

      final result = await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
      );

      expect(result.succeeded, isTrue);
      expect(result.revision, 1);

      final body = transport.lastBody;
      final ciphertext = body['ciphertext']! as String;

      final digest = await Sha256().hash(utf8.encode(ciphertext));
      final expected = digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      expect(
        body['ciphertext_sha256'],
        expected,
        reason: 'The server hashes the ciphertext string it receives.',
      );
      expect(body['base_revision'], 0);
      expect(body['device_id'], deviceId);

      // The version the envelope gave itself, not this build's newest. No
      // sync key went in, so what was sealed is a v3 -- and a revision
      // announced as v4 is one an older build refuses although it could open
      // it.
      expect(body['schema_version'], kBackupSchemaVersionWithoutSyncKey);
      expect(
        (jsonDecode(ciphertext) as Map<String, dynamic>)['schema_version'],
        body['schema_version'],
      );
    });

    test('a backup carrying a sync key is announced as v4', () async {
      enqueueHead();
      enqueueUploadAccepted();

      await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
        syncKey: Uint8List.fromList(List<int>.filled(32, 7)),
      );

      final body = transport.lastBody;

      expect(body['schema_version'], kBackupSchemaVersion);
      expect(
        (jsonDecode(body['ciphertext']! as String)
            as Map<String, dynamic>)['schema_version'],
        kBackupSchemaVersion,
      );
    });

    test('the uploaded body carries no plaintext', () async {
      await db
          .into(db.workspaces)
          .insert(
            WorkspacesCompanion.insert(
              id: 'w1',
              name: 'secret-workspace-name',
              createdAt: DateTime.now(),
            ),
          );

      enqueueHead();
      enqueueUploadAccepted();

      await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
      );

      final raw = transport.lastRequest!.body!;

      expect(raw, isNot(contains('secret-workspace-name')));
      expect(raw, isNot(contains(passphrase)));
    });

    test('uses the head the server reports as the base revision', () async {
      enqueueHead(currentRevision: 7);
      enqueueUploadAccepted(revision: 8);

      await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
      );

      expect(transport.lastBody['base_revision'], 7);
    });

    test('the revision this device knows is the base', () async {
      enqueueHead(currentRevision: 7);
      enqueueUploadAccepted(revision: 8);

      final result = await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
        expectedRevision: 7,
      );

      expect(result.succeeded, isTrue);
      expect(transport.lastBody['base_revision'], 7);
    });

    test('clears the pending upload id once the server accepts', () async {
      enqueueHead();
      enqueueUploadAccepted();

      await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
      );

      expect(pendingUploadId, isNull);
    });
  });

  group('idempotency', () {
    test('keeps the upload id when the reply never arrives', () async {
      enqueueHead();
      transport.enqueueTransportFailure(timedOut: true);

      final result = await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
      );

      expect(result.succeeded, isFalse);
      expect(result.failure, CloudBackupFailure.unavailable);
      expect(
        pendingUploadId,
        'upload-1',
        reason:
            'A dropped reply is indistinguishable from a dropped request; only '
            'a kept id lets the retry be recognised as the same write.',
      );
    });

    test('a retry reuses the same id rather than minting a new one', () async {
      enqueueHead();
      transport.enqueueTransportFailure();

      await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
      );

      enqueueHead();
      enqueueUploadAccepted();

      await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
      );

      expect(
        transport.lastBody['upload_id'],
        'upload-1',
        reason: 'A second id would store a duplicate revision.',
      );
      expect(uploadIdCounter, 1);
    });
  });

  group('failures', () {
    test('a size over the plan limit never reaches the network', () async {
      final result = await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 16,
      );

      expect(result.succeeded, isFalse);
      expect(result.failure, CloudBackupFailure.tooLarge);
      expect(result.message, contains('your plan allows'));
      expect(
        transport.sent,
        isEmpty,
        reason:
            'The client knows the limit; spending a request to learn it '
            'again is waste.',
      );
    });

    test('a conflict reports the server head and does not overwrite', () async {
      enqueueHead();
      transport.enqueue(
        status: 409,
        body: {
          'code': 'sync_conflict',
          'message': 'The base revision does not match current vault head.',
          'details': {'current_revision': 9, 'current_hash': 'deadbeef'},
        },
      );

      final result = await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
      );

      expect(result.failure, CloudBackupFailure.conflict);
      expect(result.serverRevision, 9);
      expect(transport.pending, 0);
    });

    test(
      'a head past the known revision is a conflict, and nothing is sent',
      () async {
        // Another device backed up after this one last wrote or restored.
        // Basing the upload on the fresh head would bury that backup under this
        // device's older data without anyone having been asked.
        enqueueHead(currentRevision: 7);

        final result = await service.upload(
          db: db,
          passphrase: passphrase,
          deviceId: deviceId,
          maxSizeBytes: 5 * 1024 * 1024,
          expectedRevision: 5,
        );

        expect(result.failure, CloudBackupFailure.conflict);
        expect(result.serverRevision, 7);
        expect(transport.sent, hasLength(1), reason: 'Only the head is read.');
        expect(transport.lastRequest!.method, 'GET');
        expect(
          pendingUploadId,
          isNull,
          reason: 'Nothing was sent, so no id may stay reserved for it.',
        );
      },
    );

    test('an empty vault has nothing to conflict with', () async {
      // Deleted from another device or the web panel: the revision this
      // device remembers no longer exists, and refusing on it would refuse
      // every backup from here on.
      enqueueHead();
      enqueueUploadAccepted();

      final result = await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
        expectedRevision: 5,
      );

      expect(result.succeeded, isTrue);
      expect(transport.lastBody['base_revision'], 0);
    });

    test('a resumed upload leaves the conflict to the server', () async {
      // The head moved because of this very upload, whose reply was lost.
      // Only the server can recognise the id and hand that revision back.
      pendingUploadId = 'upload-9';
      enqueueHead(currentRevision: 8);
      enqueueUploadAccepted(revision: 8);

      final result = await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
        expectedRevision: 7,
      );

      expect(result.succeeded, isTrue);
      expect(transport.lastBody['upload_id'], 'upload-9');
      expect(transport.lastBody['base_revision'], 7);
    });

    test('force ignores the known revision', () async {
      enqueueHead(currentRevision: 9);
      enqueueUploadAccepted(revision: 10);

      final result = await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
        expectedRevision: 5,
        force: true,
      );

      expect(result.succeeded, isTrue);
      expect(transport.lastBody['base_revision'], 9);
    });

    test('force re-reads the head and uploads on top of it', () async {
      enqueueHead();
      transport.enqueue(
        status: 409,
        body: {
          'code': 'sync_conflict',
          'message': 'stale',
          'details': {'current_revision': 9},
        },
      );
      enqueueHead(currentRevision: 9);
      enqueueUploadAccepted(revision: 10);

      final result = await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
        force: true,
      );

      expect(result.succeeded, isTrue);
      expect(result.revision, 10);
      expect(transport.lastBody['base_revision'], 9);
      expect(
        transport.lastBody['upload_id'],
        'upload-2',
        reason:
            'The forced write is a different write; reusing the reserved id '
            'would make the server return the revision that already lost.',
      );
    });

    test('the plan size limit is told apart from a throttle', () async {
      // Both arrive as 429 rate_limited; only details.max_size_bytes differs.
      enqueueHead();
      transport.enqueue(
        status: 429,
        body: {
          'code': 'rate_limited',
          'message': 'Backup payload exceeds plan limit of 5242880 bytes.',
          'details': {'size_bytes': 9000000, 'max_size_bytes': 5242880},
        },
      );

      final result = await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 0,
      );

      expect(result.failure, CloudBackupFailure.tooLarge);
    });

    test('a genuine throttle surfaces the retry delay', () async {
      enqueueHead();
      transport.enqueue(
        status: 429,
        body: {
          'code': 'rate_limited',
          'message': 'Too many requests.',
          'details': <String, Object?>{},
        },
        headers: {'Retry-After': '30'},
      );

      final result = await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 0,
      );

      expect(result.failure, CloudBackupFailure.throttled);
      expect(result.message, contains('30'));
    });

    test('a 403 reads as the plan, not as a server fault', () async {
      enqueueHead();
      transport.enqueue(
        status: 403,
        body: {
          'code': 'forbidden',
          'message': 'Entitlement required.',
          'details': <String, Object?>{},
        },
      );

      final result = await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 0,
      );

      expect(result.failure, CloudBackupFailure.notEntitled);
    });
  });

  group('restore', () {
    /// Uploads once against a fake server and returns the envelope it sent.
    Future<String> sealedEnvelope() async {
      enqueueHead();
      enqueueUploadAccepted();

      await service.upload(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
      );

      return transport.lastBody['ciphertext']! as String;
    }

    Future<String> sha256Hex(String value) async {
      final digest = await Sha256().hash(utf8.encode(value));

      return digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
    }

    test('round-trips a backup into a second database', () async {
      await db
          .into(db.workspaces)
          .insert(
            WorkspacesCompanion.insert(
              id: 'w1',
              name: 'Restored Workspace',
              createdAt: DateTime.now(),
            ),
          );

      final envelope = await sealedEnvelope();

      transport.enqueue(
        body: {
          'data': {
            'id': '01REV00000000000000000000',
            'revision': 1,
            'base_revision': 0,
            'device_id': deviceId,
            'schema_version': kBackupSchemaVersion,
            'encryption_version': kEncryptionVersion,
            'ciphertext_sha256': await sha256Hex(envelope),
            'size_bytes': envelope.length,
            'ciphertext': envelope,
          },
        },
      );

      final target = AppDatabase(NativeDatabase.memory());
      addTearDown(target.close);

      final result = await service.restore(
        db: target,
        revision: 1,
        secret: passphrase,
      );

      expect(result.secretsRecovered, isTrue);
      // v3, not v4: no sync key was handed to the seal, and a v4 envelope is
      // refused outright by a build that reads up to v3. One is only written
      // when it holds something a v3 cannot.
      expect(result.schemaVersion, kBackupSchemaVersionWithoutSyncKey);

      // The database seeds a default workspace on creation, so the restored
      // row is an addition rather than the only one.
      final restored = await target.select(target.workspaces).get();
      expect(restored.map((w) => w.name), contains('Restored Workspace'));
    });

    test('a checksum mismatch aborts before anything is written', () async {
      final envelope = await sealedEnvelope();

      transport.enqueue(
        body: {
          'data': {
            'id': '01REV00000000000000000000',
            'revision': 1,
            'ciphertext_sha256': 'f' * 64,
            'size_bytes': envelope.length,
            'ciphertext': envelope,
          },
        },
      );

      final target = AppDatabase(NativeDatabase.memory());
      addTearDown(target.close);

      await expectLater(
        service.restore(db: target, revision: 1, secret: passphrase),
        throwsA(isA<BackupEnvelopeException>()),
      );

      expect(
        (await target.select(target.workspaces).get()).map((w) => w.id),
        isNot(contains('w1')),
        reason: 'Nothing from the backup may land when the checksum fails.',
      );
    });

    test('a wrong passphrase writes nothing', () async {
      final envelope = await sealedEnvelope();

      transport.enqueue(
        body: {
          'data': {
            'revision': 1,
            'ciphertext_sha256': await sha256Hex(envelope),
            'ciphertext': envelope,
          },
        },
      );

      final target = AppDatabase(NativeDatabase.memory());
      addTearDown(target.close);

      await expectLater(
        service.restore(db: target, revision: 1, secret: 'wrong passphrase'),
        throwsA(isA<BackupEnvelopeException>()),
      );

      expect(
        (await target.select(target.workspaces).get()).map((w) => w.id),
        isNot(contains('w1')),
      );
    });

    test('a revision with no ciphertext is refused', () async {
      transport.enqueue(
        body: {
          'data': {'revision': 1, 'ciphertext_sha256': 'a' * 64},
        },
      );

      await expectLater(
        service.restore(db: db, revision: 1, secret: passphrase),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });
  });

  group('vault metadata', () {
    test('decodes the pinned vault head fixture', () async {
      final fixture = ContractFixture.load('sync.vault.get');
      transport.enqueue(status: fixture.status, body: fixture.body);

      final head = await service.head();

      expect(head.currentRevision, 1);
      expect(head.currentHash, isNotNull);
      expect(head.isEmpty, isFalse);
    });

    test('decodes the pinned revisions index fixture', () async {
      final fixture = ContractFixture.load('sync.revisions.index');
      transport.enqueue(status: fixture.status, body: fixture.body);

      final revisions = await service.revisions();

      expect(revisions, hasLength(1));
      expect(revisions.single.revision, 1);
      expect(revisions.single.ciphertextSha256, isNotEmpty);
      expect(
        revisions.single.ciphertext,
        isNull,
        reason: 'The index carries metadata only.',
      );
    });

    test('an empty vault reads as revision zero', () async {
      transport.enqueue(
        body: {
          'data': {'id': '01V', 'current_revision': 0, 'bytes_used': 0},
        },
      );

      final head = await service.head();

      expect(head.isEmpty, isTrue);
      expect(head.currentRevision, 0);
    });

    test('deleting the vault clears any reserved upload id', () async {
      pendingUploadId = 'upload-1';
      transport.enqueue(
        body: {
          'data': {'message': 'deleted'},
        },
      );

      await service.deleteVault();

      expect(pendingUploadId, isNull);
    });
  });
}
