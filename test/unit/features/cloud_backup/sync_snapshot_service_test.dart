import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_client.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/core/sync/e2ee_cloud_sync_service.dart';
import 'package:shellvibe/core/sync/sync_journal.dart';
import 'package:shellvibe/features/cloud_backup/data/cloud_backup_api.dart';
import 'package:shellvibe/features/cloud_backup/domain/cloud_backup_service.dart';
import 'package:shellvibe/features/cloud_backup/domain/sync_snapshot_service.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

import '../../../support/fake_api_transport.dart';

/// The ground a device joining automatic sync starts from.
///
/// It lives in its own vault, it always carries what automatic sync carries,
/// and a revision that carries less is not a starting point -- a device that
/// began from one would be missing a category with nothing left to fill it in
/// from, and would not be told.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeApiTransport transport;
  late AppDatabase db;
  late E2EECloudSyncService e2ee;
  late SyncSnapshotService ground;
  late String? backupUploadId;
  late String? syncUploadId;

  const passphrase = 'a sync passphrase';
  const deviceId = '01DEVICEULID00000000000000';

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});

    transport = FakeApiTransport();
    db = AppDatabase(NativeDatabase.memory());

    final vaultKeyService = VaultKeyService(
      encryptionEngine: EncryptionEngine(),
      secureStorageService: SecureStorageService(),
    );
    await vaultKeyService.getDek();

    e2ee = E2EECloudSyncService(vaultKeyService: vaultKeyService);
    backupUploadId = null;
    syncUploadId = null;

    final client = ApiClient(
      transport: transport,
      tokenProvider: () async => 'test-token',
    );

    ground = SyncSnapshotService.over(
      backupService: CloudBackupService(
        api: CloudBackupApi(client: client),
        sync: e2ee,
        readPendingUploadId: () async => backupUploadId,
        writePendingUploadId: (id) async => backupUploadId = id,
        newUploadId: () => 'backup-upload',
      ),
      syncApi: CloudBackupApi(client: client, kind: VaultKind.sync),
      readPendingUploadId: () async => syncUploadId,
      writePendingUploadId: (id) async => syncUploadId = id,
    );
  });

  tearDown(() => db.close());

  Uint8List syncKey() => Uint8List.fromList(List.filled(32, 7));

  Future<void> addHost(String id) => db
      .into(db.hosts)
      .insert(
        HostsCompanion.insert(
          id: id,
          workspaceId: 'default',
          label: id,
          hostname: '$id.example.com',
          createdAt: DateTime.now(),
        ),
      );

  void enqueueHead({int currentRevision = 0}) => transport.enqueue(
    body: {
      'data': {
        'id': '01VAULT0000000000000000000',
        'current_revision': currentRevision,
        'current_hash': currentRevision == 0 ? null : 'abc',
        'bytes_used': 0,
        'updated_at': null,
      },
    },
  );

  void enqueueStored(int revision) => transport.enqueue(
    status: 201,
    body: {
      'data': {
        'id': '01REV00000000000000000000',
        'revision': revision,
        'base_revision': revision - 1,
        'device_id': deviceId,
        'schema_version': 4,
        'encryption_version': 2,
        'ciphertext_sha256': 'x' * 64,
        'size_bytes': 10,
        'created_at': null,
      },
    },
  );

  void enqueueRevisionList(List<int> revisions) => transport.enqueue(
    body: {
      'data': [
        for (final revision in revisions)
          {
            'id': '01REV0000000000000000000$revision',
            'revision': revision,
            'base_revision': revision - 1,
            'device_id': 'writer-device',
            'schema_version': 4,
            'encryption_version': 2,
            'ciphertext_sha256': 'x' * 64,
            'size_bytes': 10,
            'created_at': null,
          },
      ],
      'meta': {'count': revisions.length},
    },
  );

  void enqueueRevision(int revision, String ciphertext) => transport.enqueue(
    body: {
      'data': {
        'id': '01REV0000000000000000000$revision',
        'revision': revision,
        'base_revision': revision - 1,
        'device_id': 'writer-device',
        'schema_version': 4,
        'encryption_version': 2,
        'ciphertext_sha256': 'x' * 64,
        'size_bytes': ciphertext.length,
        'created_at': null,
        'ciphertext': ciphertext,
      },
    },
  );

  group('writing the ground', () {
    test('it addresses the sync vault, not the backups', () async {
      await addHost('h1');
      enqueueHead();
      enqueueStored(1);

      final result = await ground.write(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
        syncKey: syncKey(),
      );

      expect(result.succeeded, isTrue);
      expect(transport.sent.first.url.query, contains('kind=sync'));
      expect(transport.lastBody['kind'], 'sync');
    });

    test('it carries the sync scope whatever this device syncs', () async {
      // A device that syncs only hosts still holds everything else, and a
      // ground missing a category is one nothing later fills in.
      await addHost('h1');
      enqueueHead();
      enqueueStored(1);

      await ground.write(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
        syncKey: syncKey(),
      );

      final opened = await BackupEnvelope().open(
        envelopeJson: transport.lastBody['ciphertext']! as String,
        secret: passphrase,
      );
      final payload = jsonDecode(opened.payloadJson) as Map<String, dynamic>;

      expect(
        BackupScope.fromManifest(payload['included']).coversSyncGround,
        isTrue,
      );
    });

    test('it records the clock the device is at', () async {
      db.syncJournal = SyncJournal(db: db, deviceId: deviceId);
      await db.syncJournal!.acknowledgePull(17);
      await addHost('h1');
      enqueueHead();
      enqueueStored(1);

      await ground.write(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
        syncKey: syncKey(),
      );

      final opened = await BackupEnvelope().open(
        envelopeJson: transport.lastBody['ciphertext']! as String,
        secret: passphrase,
      );

      // Without this the device that restores it counts from zero and replays
      // a log it has already restored past.
      expect(
        (jsonDecode(opened.payloadJson) as Map<String, dynamic>)['sync_clock'],
        17,
      );
    });

    test('it seals the sync key in so other devices can learn it', () async {
      await addHost('h1');
      enqueueHead();
      enqueueStored(1);

      await ground.write(
        db: db,
        passphrase: passphrase,
        deviceId: deviceId,
        maxSizeBytes: 5 * 1024 * 1024,
        syncKey: syncKey(),
      );

      final opened = await BackupEnvelope().open(
        envelopeJson: transport.lastBody['ciphertext']! as String,
        secret: passphrase,
      );

      expect(await opened.syncKey!.extractBytes(), syncKey());
    });
  });

  group('reading the ground', () {
    Future<String> sealed({
      required BackupScope scope,
      int syncClock = 5,
    }) async {
      await addHost('remote-host');
      final envelope = await e2ee.exportEncryptedBackup(
        db: db,
        masterPassword: passphrase,
        scope: scope,
        syncClock: syncClock,
        syncKey: syncKey(),
      );
      await db.delete(db.hosts).go();

      return envelope;
    }

    test('an empty vault is not an error, it is the first device', () async {
      enqueueRevisionList([]);

      final result = await ground.readGround(secret: passphrase);

      expect(result.ground, isNull);
      expect(result.problem, SyncGroundProblem.none);
    });

    test('the newest complete revision is the starting point', () async {
      final envelope = await sealed(scope: BackupScope.syncGround);

      enqueueRevisionList([2]);
      enqueueRevision(2, envelope);
      enqueueRevision(2, envelope);

      final result = await ground.readGround(secret: passphrase);

      expect(result.ground, isNotNull);
      expect(result.ground!.revision, 2);
      expect(result.ground!.syncClock, 5);
      expect(result.ground!.deviceId, 'writer-device');
    });

    test('a partial revision is walked past, not accepted', () async {
      // It would restore, and leave a category missing that no later snapshot
      // or operation fills in -- silently, which is the whole problem.
      final partial = await sealed(
        scope: BackupScope.of([BackupCategory.hosts]),
      );
      final complete = await sealed(scope: BackupScope.syncGround);

      enqueueRevisionList([3, 2]);
      enqueueRevision(3, partial);
      enqueueRevision(2, complete);
      enqueueRevision(2, complete);

      final result = await ground.readGround(secret: passphrase);

      expect(result.ground!.revision, 2);
    });

    test('nothing complete says so rather than starting anyway', () async {
      final partial = await sealed(
        scope: BackupScope.of([BackupCategory.hosts]),
      );

      enqueueRevisionList([1]);
      enqueueRevision(1, partial);

      final result = await ground.readGround(secret: passphrase);

      expect(result.ground, isNull);
      expect(result.problem, SyncGroundProblem.allPartial);
    });

    test('a wrong secret is told apart from a partial vault', () async {
      final complete = await sealed(scope: BackupScope.syncGround);

      enqueueRevisionList([1]);
      enqueueRevision(1, complete);

      final result = await ground.readGround(secret: 'not the passphrase');

      expect(result.ground, isNull);
      expect(result.problem, SyncGroundProblem.cannotOpen);
    });
  });

  group('applying the ground', () {
    test('it merges rather than replacing', () async {
      // The reason the order two devices switch sync on stops mattering: this
      // device keeps what it has and gains what the ground carries.
      await addHost('remote-host');
      final envelope = await e2ee.exportEncryptedBackup(
        db: db,
        masterPassword: passphrase,
        scope: BackupScope.syncGround,
        syncClock: 5,
      );
      await db.delete(db.hosts).go();
      await addHost('local-host');

      await ground.apply(
        db: db,
        secret: passphrase,
        ground: SyncGround(
          revision: 1,
          deviceId: 'writer-device',
          syncClock: 5,
          ciphertext: envelope,
        ),
      );

      final ids = (await db.select(db.hosts).get()).map((h) => h.id).toSet();
      expect(ids, {'local-host', 'remote-host'});
    });
  });
}
