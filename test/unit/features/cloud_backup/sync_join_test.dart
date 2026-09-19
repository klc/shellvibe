import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_exception.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/core/sync/e2ee_cloud_sync_service.dart';
import 'package:shellvibe/core/sync/sync_engine.dart';
import 'package:shellvibe/core/sync/sync_journal.dart';
import 'package:shellvibe/features/cloud_backup/data/cloud_backup_api.dart';
import 'package:shellvibe/features/cloud_backup/data/sync_operations_api.dart';
import 'package:shellvibe/features/cloud_backup/domain/cloud_backup_service.dart';
import 'package:shellvibe/features/cloud_backup/domain/sync_join_service.dart';
import 'package:shellvibe/features/cloud_backup/domain/sync_snapshot_service.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// Joining an account that is already syncing, from both directions.
///
/// The question the design turns on is whether the order two devices switch
/// sync on decides whose data survives. It must not: a phone with two hosts
/// and a desktop with sixty end at sixty-two either way round.
///
/// The vault and the log are in memory. What is real is everything that can
/// lose data: the merge, the seed, the clocks, the versions and the state that
/// lets an interrupted join finish.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Vault vault;
  late _Log log;
  late Uint8List syncKey;

  const passphrase = 'a joining passphrase';

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    vault = _Vault();
    log = _Log();
    syncKey = BackupEnvelope().generateSyncKey();
  });

  Future<_Device> device(String id) async {
    final db = AppDatabase(NativeDatabase.memory());
    final journal = SyncJournal(db: db, deviceId: id);
    db.syncJournal = journal;
    addTearDown(db.close);

    final vaultKeyService = VaultKeyService(
      encryptionEngine: EncryptionEngine(),
      secureStorageService: SecureStorageService(),
    );
    await vaultKeyService.getDek();

    final e2ee = E2EECloudSyncService(vaultKeyService: vaultKeyService);
    String? pendingUpload;

    final ground = SyncSnapshotService(
      backups: CloudBackupService(
        api: vault,
        sync: e2ee,
        readPendingUploadId: () async => pendingUpload,
        writePendingUploadId: (value) async => pendingUpload = value,
        newUploadId: () => '$id-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );

    final engine = SyncEngine(
      db: db,
      journal: journal,
      api: log,
      syncKey: SecretKey(syncKey),
    );

    return _Device(
      id: id,
      db: db,
      journal: journal,
      engine: engine,
      join: SyncJoinService(
        db: db,
        journal: journal,
        ground: ground,
        engine: engine,
      ),
    );
  }

  group('the first device', () {
    test('writes the ground and queues nothing', () async {
      final desktop = await device('desktop');
      await desktop.addHosts(60);

      final result = await desktop.joinSync(syncKey, passphrase);

      expect(result.succeeded, isTrue);
      expect(result.wroteFirstGround, isTrue);
      expect(vault.stored, hasLength(1));

      // Nothing to tell: the rows are in the ground every other device starts
      // from, so sending them would spend the write budget on nobody.
      expect(await desktop.journal.pending(), isEmpty);
    });

    test('stamps its rows so an old operation cannot overwrite them', () async {
      final desktop = await device('desktop');
      await desktop.addHosts(2);

      await desktop.joinSync(syncKey, passphrase);

      final version = await desktop.journal.versionFor(
        entityType: 'hosts',
        entityId: 'host-1',
      );

      expect(version, isNotNull);
    });
  });

  group('joining an account that already has data', () {
    test('an empty device takes what is there', () async {
      final desktop = await device('desktop');
      await desktop.addHosts(60);
      await desktop.joinSync(syncKey, passphrase);

      final phone = await device('phone');
      final result = await phone.joinSync(syncKey, passphrase);

      expect(result.succeeded, isTrue);
      expect(await phone.hostCount(), 60);
      expect(result.seeded, 0);
    });

    test('a device with its own data keeps it and contributes it', () async {
      // The scenario in the design note, in the order that used to be unsafe:
      // the small device joins first and writes the ground, then the large one
      // arrives.
      final phone = await device('phone');
      await phone.addHosts(2, prefix: 'phone');
      await phone.joinSync(syncKey, passphrase);

      final desktop = await device('desktop');
      await desktop.addHosts(60);
      final result = await desktop.joinSync(syncKey, passphrase);

      expect(result.succeeded, isTrue);
      expect(await desktop.hostCount(), 62);
      expect(result.seeded, 60);
      expect(result.pushed, greaterThan(0));

      // And the phone catches up from the log.
      await phone.engine.pull();
      expect(await phone.hostCount(), 62);
    });

    test('the order the two join in does not change the outcome', () async {
      final desktop = await device('desktop');
      await desktop.addHosts(60);
      await desktop.joinSync(syncKey, passphrase);

      final phone = await device('phone');
      await phone.addHosts(2, prefix: 'phone');
      await phone.joinSync(syncKey, passphrase);

      expect(await phone.hostCount(), 62);

      await desktop.engine.pull();
      expect(await desktop.hostCount(), 62);
    });

    test('rows the ground brought are not sent back', () async {
      // They were just downloaded. Re-uploading them spends a thirty-per-
      // minute write budget saying what the account already holds.
      final desktop = await device('desktop');
      await desktop.addHosts(60);
      await desktop.joinSync(syncKey, passphrase);

      final phone = await device('phone');
      await phone.addHosts(1, prefix: 'phone');
      final result = await phone.joinSync(syncKey, passphrase);

      expect(result.seeded, 1);
    });

    test('a seeding device refreshes the ground', () async {
      // Otherwise the ground stays the small one, and a third device that
      // joins after the log is pruned starts from two hosts and is not told
      // about the other sixty.
      final phone = await device('phone');
      await phone.addHosts(2, prefix: 'phone');
      await phone.joinSync(syncKey, passphrase);

      final desktop = await device('desktop');
      await desktop.addHosts(60);
      final result = await desktop.joinSync(syncKey, passphrase);

      expect(result.refreshedGround, isTrue);
      expect(vault.stored, hasLength(2));

      // A third device, with the log gone.
      log.expireCursors = true;
      final tablet = await device('tablet');
      await tablet.joinSync(syncKey, passphrase);

      expect(await tablet.hostCount(), 62);
    });
  });

  group('an interrupted join', () {
    test('finishes on the next start instead of calling itself done', () async {
      final desktop = await device('desktop');
      await desktop.addHosts(60);
      await desktop.joinSync(syncKey, passphrase);

      final phone = await device('phone');
      await phone.addHosts(3, prefix: 'phone');

      // Stops after the merge and the queue, before anything is sent.
      vault.failUploads = true;
      log.failPushes = true;
      await expectLater(
        phone.joinSync(syncKey, passphrase),
        throwsA(isA<Object>()),
      );

      expect(await phone.journal.readJoinState(), SyncJoinState.applied);
      expect(await phone.journal.pending(), hasLength(3));

      vault.failUploads = false;
      log.failPushes = false;
      final result = await phone.joinSync(syncKey, passphrase);

      expect(result.succeeded, isTrue);
      expect(result.pushed, 3);
      expect(await phone.journal.readJoinState(), SyncJoinState.done);
    });

    test('a finished join does nothing on the next start', () async {
      final desktop = await device('desktop');
      await desktop.addHosts(5);
      await desktop.joinSync(syncKey, passphrase);

      final before = vault.stored.length;
      final again = await desktop.joinSync(syncKey, passphrase);

      expect(again.succeeded, isTrue);
      expect(again.seeded, 0);
      expect(vault.stored, hasLength(before));
    });
  });

  group('refusing to start from the wrong thing', () {
    test('a partial ground is refused rather than half-applied', () async {
      final desktop = await device('desktop');
      await desktop.addHosts(5);
      await desktop.writePartialGround(passphrase);

      final phone = await device('phone');
      final result = await phone.joinSync(syncKey, passphrase);

      expect(result.succeeded, isFalse);
      expect(result.problem, SyncJoinProblem.noCompleteGround);
      expect(await phone.hostCount(), 0);
      expect(await phone.journal.readJoinState(), SyncJoinState.none);
    });

    test('a wrong passphrase says so and changes nothing', () async {
      final desktop = await device('desktop');
      await desktop.addHosts(5);
      await desktop.joinSync(syncKey, passphrase);

      final phone = await device('phone');
      final result = await phone.joinSync(syncKey, 'not the passphrase');

      expect(result.problem, SyncJoinProblem.cannotOpen);
      expect(await phone.hostCount(), 0);
    });
  });
}

final class _Device {
  final String id;
  final AppDatabase db;
  final SyncJournal journal;
  final SyncEngine engine;
  final SyncJoinService join;

  const _Device({
    required this.id,
    required this.db,
    required this.journal,
    required this.engine,
    required this.join,
  });

  Future<SyncJoinResult> joinSync(Uint8List key, String secret) => join.join(
    secret: secret,
    deviceId: id,
    maxSizeBytes: 5 * 1024 * 1024,
    syncKey: key,
  );

  Future<int> hostCount() async => (await db.select(db.hosts).get()).length;

  Future<void> addHosts(int count, {String prefix = 'host'}) async {
    for (var i = 1; i <= count; i++) {
      await db
          .into(db.hosts)
          .insert(
            HostsCompanion.insert(
              id: '$prefix-$i',
              workspaceId: 'default',
              label: '$prefix $i',
              hostname: '$prefix-$i.example.com',
              createdAt: DateTime.now(),
            ),
          );
    }
  }

  /// Writes a snapshot that carries less than automatic sync carries, the way
  /// a narrowed manual backup would if it were ever pointed at this vault.
  Future<void> writePartialGround(String secret) async {
    final envelope = await join.ground.backups.sync.exportEncryptedBackup(
      db: db,
      masterPassword: secret,
      scope: BackupScope.of([BackupCategory.hosts]),
      syncClock: 1,
    );

    await join.ground.backups.api.upload(
      baseRevision: 0,
      uploadId: 'partial',
      deviceId: id,
      schemaVersion: 4,
      encryptionVersion: 2,
      ciphertext: envelope,
      ciphertextSha256: '',
    );
  }
}

/// The sync vault, in memory.
final class _Vault implements VaultTransport {
  final List<BackupRevision> stored = [];

  bool failUploads = false;

  @override
  VaultKind get kind => VaultKind.sync;

  @override
  Future<VaultHead> head() async => VaultHead(
    id: 'vault',
    currentRevision: stored.length,
    currentHash: stored.isEmpty ? null : stored.last.ciphertextSha256,
  );

  /// Newest first, the way the server orders them.
  @override
  Future<List<BackupRevision>> revisions() async =>
      stored.reversed.toList(growable: false);

  @override
  Future<BackupRevision> revision(int revision) async =>
      stored.firstWhere((r) => r.revision == revision);

  @override
  Future<BackupRevision> upload({
    required int baseRevision,
    required String uploadId,
    required String deviceId,
    required int schemaVersion,
    required int encryptionVersion,
    required String ciphertext,
    required String ciphertextSha256,
  }) async {
    if (failUploads) {
      throw const ApiTransportException('vault unreachable');
    }

    final written = BackupRevision(
      id: 'rev-${stored.length + 1}',
      revision: stored.length + 1,
      baseRevision: baseRevision,
      deviceId: deviceId,
      schemaVersion: schemaVersion,
      encryptionVersion: encryptionVersion,
      ciphertextSha256: ciphertextSha256,
      sizeBytes: ciphertext.length,
      ciphertext: ciphertext,
    );

    stored.add(written);

    return written;
  }

  @override
  Future<void> deleteVault() async => stored.clear();
}

/// The operation log, in memory.
final class _Log implements SyncOperationTransport {
  final List<SyncOperationDto> operations = [];

  bool expireCursors = false;
  bool failPushes = false;

  @override
  Future<int> push(List<SyncOperationDto> batch) async {
    if (failPushes) throw const ApiTransportException('log unreachable');
    operations.addAll(batch);

    return batch.length;
  }

  @override
  Future<SyncOperationPage> pull({
    required int sinceClock,
    int limit = 100,
  }) async {
    if (expireCursors) {
      throw const ApiException(
        statusCode: 409,
        code: ApiErrorCode.syncCursorExpired,
        message: 'Operations after this cursor have been pruned.',
      );
    }

    final ordered = [...operations]
      ..sort((a, b) {
        final byClock = a.logicalClock.compareTo(b.logicalClock);

        return byClock != 0 ? byClock : a.id.compareTo(b.id);
      });

    final after = ordered
        .where((o) => o.logicalClock > sinceClock)
        .toList(growable: false);
    final page = after.take(limit).toList(growable: false);

    return SyncOperationPage(
      operations: page,
      maxClock: page.isEmpty ? sinceClock : page.last.logicalClock,
      hasMore: after.length > page.length,
    );
  }
}
