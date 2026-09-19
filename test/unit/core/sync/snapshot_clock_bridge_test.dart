import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/core/sync/e2ee_cloud_sync_service.dart';
import 'package:shellvibe/core/sync/sync_journal.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// A snapshot has to say where it sits in the operation log, and a restore has
/// to believe it.
///
/// Both halves existed and neither was connected: `exportEncryptedBackup` took
/// a `syncClock` nobody passed, and `importEncryptedBackup` read one back into
/// a field nobody used. The result was a restored device that counted from
/// zero -- it replayed the whole log it had just restored past, and every row
/// it restored stood at no clock at all, so the first operation to mention one
/// won by default.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase source;
  late AppDatabase target;
  late E2EECloudSyncService sync;

  const passphrase = 'snapshot clock passphrase';

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    source = AppDatabase(NativeDatabase.memory());
    target = AppDatabase(NativeDatabase.memory());

    final vaultKeyService = VaultKeyService(
      encryptionEngine: EncryptionEngine(),
      secureStorageService: SecureStorageService(),
    );
    await vaultKeyService.getDek();

    sync = E2EECloudSyncService(vaultKeyService: vaultKeyService);
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  Future<void> addHost(AppDatabase db, String id) => db
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

  Future<String> exportAt(int? clock) => sync.exportEncryptedBackup(
    db: source,
    masterPassword: passphrase,
    syncClock: clock,
  );

  test('the snapshot records the clock it was taken at', () async {
    await addHost(source, 'h1');

    final opened = await sync.importEncryptedBackup(
      backupPackageJson: await exportAt(42),
      db: target,
      masterPassword: passphrase,
    );

    expect(opened.syncClock, 42);
  });

  test('restoring moves the cursor to the snapshot clock', () async {
    await addHost(source, 'h1');
    target.syncJournal = SyncJournal(db: target, deviceId: 'target-device');

    await sync.importEncryptedBackup(
      backupPackageJson: await exportAt(42),
      db: target,
      masterPassword: passphrase,
    );

    final state = await target.syncJournal!.readState();

    // Both clocks: the cursor says what not to ask for again, and the Lamport
    // clock says the next local change is ordered after the snapshot.
    expect(state.pulledThroughClock, 42);
    expect(state.lastSeenClock, 42);
  });

  test('restored rows stand at the snapshot clock', () async {
    await addHost(source, 'h1');
    target.syncJournal = SyncJournal(db: target, deviceId: 'target-device');

    await sync.importEncryptedBackup(
      backupPackageJson: await exportAt(42),
      db: target,
      masterPassword: passphrase,
      snapshotDeviceId: 'source-device',
    );

    final version = await target.syncJournal!.versionFor(
      entityType: 'hosts',
      entityId: 'h1',
    );

    // Without this a row restored from a snapshot has no version, so an
    // operation older than the snapshot still overwrites it.
    expect(version, isNotNull);
    expect(version!.logicalClock, 42);
    expect(version.deviceId, 'source-device');
  });

  test('a row the restore skipped is not stamped', () async {
    // The payload names it; the restore drops it because its host never
    // arrives. Stamping it anyway would defend a row that is not there.
    await source
        .into(source.hosts)
        .insert(
          HostsCompanion.insert(
            id: 'h1',
            workspaceId: 'default',
            label: 'h1',
            hostname: 'h1.example.com',
            createdAt: DateTime.now(),
          ),
        );
    await source
        .into(source.portForwardRules)
        .insert(
          PortForwardRulesCompanion.insert(
            id: 'p1',
            hostId: 'h1',
            type: 'local',
            localPort: 8080,
            remoteHost: const Value('localhost'),
            remotePort: const Value(80),
          ),
        );

    final backup = await exportAt(42);
    target.syncJournal = SyncJournal(db: target, deviceId: 'target-device');

    // Strip the hosts out of the payload the way a narrowed scope would, so
    // the port forward has nothing to attach to.
    await sync.importEncryptedBackup(
      backupPackageJson: await _withoutHosts(sync, backup, passphrase),
      db: target,
      masterPassword: passphrase,
    );

    expect(
      await target.syncJournal!.versionFor(
        entityType: 'port_forward_rules',
        entityId: 'p1',
      ),
      isNull,
    );
  });

  test('restoring an older revision does not rewind the cursor', () async {
    await addHost(source, 'h1');
    target.syncJournal = SyncJournal(db: target, deviceId: 'target-device');
    await target.syncJournal!.acknowledgePull(100);

    await sync.importEncryptedBackup(
      backupPackageJson: await exportAt(42),
      db: target,
      masterPassword: passphrase,
    );

    final state = await target.syncJournal!.readState();

    // Rewinding would offer operations this device has already applied a
    // second time -- and it asked for an old revision on purpose.
    expect(state.pulledThroughClock, 100);
  });

  test('a snapshot without a clock leaves the cursor alone', () async {
    // Every backup written before this bridge existed. It must restore the
    // way it always did rather than claiming clock zero.
    await addHost(source, 'h1');
    target.syncJournal = SyncJournal(db: target, deviceId: 'target-device');
    await target.syncJournal!.acknowledgePull(7);

    await sync.importEncryptedBackup(
      backupPackageJson: await exportAt(null),
      db: target,
      masterPassword: passphrase,
    );

    final state = await target.syncJournal!.readState();
    expect(state.pulledThroughClock, 7);
    expect(
      await target.syncJournal!.versionFor(entityType: 'hosts', entityId: 'h1'),
      isNull,
    );
  });

  test('a restore without a journal attached still restores', () async {
    // Sync is off on this device. The rows have to arrive anyway.
    await addHost(source, 'h1');

    await sync.importEncryptedBackup(
      backupPackageJson: await exportAt(42),
      db: target,
      masterPassword: passphrase,
    );

    expect(await target.select(target.hosts).get(), hasLength(1));
  });
}

/// Re-seals [backup] with its `hosts` collection removed.
Future<String> _withoutHosts(
  E2EECloudSyncService sync,
  String backup,
  String passphrase,
) async {
  final envelope = BackupEnvelope();
  final opened = await envelope.open(envelopeJson: backup, secret: passphrase);
  final payload = opened.payloadJson.replaceFirst(
    RegExp(r'"hosts":\[.*?\],'),
    '"hosts":[],',
  );

  return envelope.seal(
    payloadJson: payload,
    dek: opened.backupDek!,
    passphrase: passphrase,
  );
}
