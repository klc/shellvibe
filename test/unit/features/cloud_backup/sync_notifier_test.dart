import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/backup_scope_store.dart';
import 'package:shellvibe/core/sync/e2ee_cloud_sync_service.dart';
import 'package:shellvibe/core/sync/sync_journal.dart';
import 'package:shellvibe/features/cloud_backup/data/cloud_backup_store.dart';
import 'package:shellvibe/features/cloud_backup/presentation/notifiers/sync_notifier.dart';
import 'package:shellvibe/features/settings/presentation/notifiers/backup_scope_notifier.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

import '../../../support/fast_crypto.dart';
import '../../../support/fake_sync_server.dart';
import '../../../support/signed_in_container.dart';

/// What automatic sync does once it is switched on: that it actually runs,
/// stops when told to, says so when joining fails, and ends up holding the
/// same key as the rest of the account.
///
/// Driven end to end: a signed-in device, the real journal, engine, join and
/// stores, and an in-memory server holding the sync ground and the log.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeSyncServer server;
  late ProviderContainer container;

  const passphrase = 'a long enough passphrase';

  CloudBackupStore store() => CloudBackupStore(storage: SecureStorageService());

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    server = FakeSyncServer();
    container = signedInContainer(db: db, server: server);

    await store().writePassphrase(passphrase);
    await BackupScopeStore(
      storage: SecureStorageService(),
    ).writeAutoSyncEnabled(true);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  SyncState current() => container.read(syncProvider).requireValue;

  Future<SyncNotifier> started() async {
    await container.read(syncProvider.future);

    return container.read(syncProvider.notifier);
  }

  /// Waits for the join the build started, and the first pass after it.
  Future<void> joined(SyncNotifier notifier) async {
    await eventually(
      () => current().lastJoin != null || current().error != null,
      reason: 'the join never reported back',
    );
    expect(current().error, isNull, reason: 'the join failed');
    // Queued behind the pass the join started, so this returns once that
    // one has finished too.
    await notifier.syncNow();
  }

  Future<void> addHost(String id) => db.hostsDao.insertHost(
    HostsCompanion.insert(
      id: id,
      workspaceId: 'default',
      label: id,
      hostname: '$id.example.com',
      createdAt: DateTime.now(),
    ),
  );

  List<Object?> pushes() => server.sent('POST', '/sync/operations');

  /// A sync ground as another device would have written it: one host, sealed
  /// with the passphrase, carrying [syncKey].
  Future<void> seedGround(Uint8List syncKey) async {
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await other.hostsDao.insertHost(
      HostsCompanion.insert(
        id: 'remote-host',
        workspaceId: 'default',
        label: 'remote-host',
        hostname: 'remote.example.com',
        createdAt: DateTime.now(),
      ),
    );

    final vaultKeys = VaultKeyService(
      encryptionEngine: fastEncryptionEngine(),
      secureStorageService: SecureStorageService(),
    );
    await vaultKeys.getDek();

    await server.seedRevision(
      'sync',
      await E2EECloudSyncService(
        vaultKeyService: vaultKeys,
        cryptoEngine: fastEncryptionEngine(),
      ).exportEncryptedBackup(
        db: other,
        masterPassword: passphrase,
        scope: BackupScope.syncGround,
        syncClock: 0,
        syncKey: syncKey,
      ),
      deviceId: 'other-device',
    );
  }

  Uint8List key(int fill) => Uint8List.fromList(List<int>.filled(32, fill));

  group('running', () {
    test('a started device sends what changes on it', () async {
      // Starting used to tear down the engine it had just built, and every
      // pass after that returned at a null check: the timers ran, nothing
      // was ever sent, and nothing reported a problem.
      final notifier = await started();
      await joined(notifier);
      expect(server.vaults['sync'], hasLength(1), reason: 'the first ground');

      await addHost('h1');
      await notifier.syncNow();

      expect(server.operations, isNotEmpty);
      expect(current().lastPushed, greaterThan(0));
    });

    test('switching it off stops sending', () async {
      final notifier = await started();
      await joined(notifier);
      final before = pushes().length;

      await container.read(autoSyncEnabledProvider.notifier).set(false);
      await container.read(syncProvider.future);
      await addHost('h1');
      await notifier.syncNow();

      expect(current().blocker, SyncBlocker.disabled);
      expect(pushes(), hasLength(before));
    });
  });

  group('joining', () {
    test('a join that cannot write the ground says so', () async {
      // Reported from inside `build`, the failure landed on a state that did
      // not exist yet, and the screen kept saying sync was watching for
      // changes while nothing had happened at all.
      server.intercept = (request) =>
          request.method == 'PUT' &&
              (jsonDecode(request.body!) as Map)['kind'] == 'sync'
          ? FakeSyncServer.error(500, 'internal_error', 'The server failed.')
          : null;

      await started();
      await eventually(() => current().error != null);

      expect(current().lastJoin, isNull);
      expect(server.vaults['sync'], isEmpty);
      expect(
        await SyncJournal(db: db, deviceId: 'device-a').readJoinState(),
        isNot(SyncJoinState.done),
      );
    });

    test('the pass after a join reports what it could not read', () async {
      // Sealed with a key this device does not hold. A join is where a
      // mismatched key shows itself first, and a pass that dropped the count
      // reported that device as a clean sync that happened to pull nothing.
      server.operations.add({
        'id': 'op-foreign',
        'device_id': 'other-device',
        'logical_clock': 1,
        'entity_type': 'a' * 32,
        'entity_id': 'b' * 32,
        'operation': 'upsert',
        'encrypted_payload': base64.encode(List<int>.filled(64, 7)),
      });

      await started();

      await eventually(
        () => current().error?.contains('could not be read') ?? false,
        reason: 'the first pass after the join reported a clean sync',
      );
    });
  });

  group('the sync key', () {
    test('a device holding a key of its own adopts the account\'s', () async {
      // Two devices that switched sync on before either had written a ground
      // each minted a key. If holding one ended the search, each would push a
      // log the other silently discards, forever.
      await store().writeSyncKey(base64.encode(key(1)));
      await seedGround(key(2));

      final notifier = await started();
      await joined(notifier);

      expect(await store().readSyncKey(), base64.encode(key(2)));
      expect(
        (await db.select(db.hosts).get()).map((h) => h.id),
        contains('remote-host'),
      );

      // What this device sent before was sealed with a key nobody else
      // holds, so it rewrites the ground under the account's key.
      await eventually(
        () => server.vaults['sync']!.last['device_id'] == 'device-a',
        reason: 'the ground was not rewritten after adopting the key',
      );
    });

    test(
      'a device that has finished joining does not re-read the ground',
      () async {
        // The log reports a mismatched key from then on. Downloading a snapshot
        // on every start to re-confirm a key that cannot change is a request
        // nobody needs.
        await store().writeSyncKey(base64.encode(key(1)));
        await SyncJournal(
          db: db,
          deviceId: 'device-a',
        ).writeJoinState(SyncJoinState.done);
        await seedGround(key(2));

        final notifier = await started();
        await joined(notifier);

        expect(await store().readSyncKey(), base64.encode(key(1)));
        expect(
          server.requests.where(
            (r) =>
                r.method == 'GET' &&
                r.url.path.contains('/sync/vault/revisions') &&
                r.url.queryParameters['kind'] == 'sync',
          ),
          isEmpty,
        );
      },
    );
  });
}
