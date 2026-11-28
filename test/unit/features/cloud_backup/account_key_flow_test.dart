import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_client.dart';
import 'package:shellvibe/core/sync/account_key.dart';
import 'package:shellvibe/core/sync/backup_scope_store.dart';
import 'package:shellvibe/core/sync/e2ee_cloud_sync_service.dart';
import 'package:shellvibe/features/cloud_backup/data/account_key_api.dart';
import 'package:shellvibe/features/cloud_backup/data/cloud_backup_store.dart';
import 'package:shellvibe/features/cloud_backup/domain/device_handoff_service.dart';
import 'package:shellvibe/features/cloud_backup/presentation/notifiers/cloud_backup_notifier.dart';
import 'package:shellvibe/features/cloud_backup/presentation/notifiers/sync_notifier.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/identities_notifier.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/vault_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

import '../../../support/cloud_backup_store.dart';
import '../../../support/fake_sync_server.dart';
import '../../../support/fast_crypto.dart';
import '../../../support/signed_in_container.dart';

/// The account key, across the devices of one account.
///
/// Every test below has more than one device in it, because that is where
/// this can go wrong: a key one device holds and another cannot reach, a
/// snapshot one wrote and another cannot open. Each device has its own
/// keychain and its own database; the server is the one thing they share.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSyncServer server;
  late _Device desktop;
  late _Device phone;

  const passphrase = 'a long enough passphrase';
  const recoveryCode = 'X4K7M-9PQR2-ABCDE-FGHJK-MNPQR-STVWX-YZ';

  CloudBackupStore store() => testCloudBackupStore();

  setUp(() {
    server = FakeSyncServer()..accountKeyEnabled = true;
    desktop = _Device('desktop', server);
    phone = _Device('phone', server);
  });

  tearDown(() async {
    for (final device in [desktop, phone]) {
      device.container?.dispose();
      await device.db.close();
    }
  });

  Future<void> switchSyncOn() => BackupScopeStore(
    storage: SecureStorageService(),
  ).writeAutoSyncEnabled(true);

  /// A device as it was before the account key: the passphrase and the
  /// recovery code in its keychain.
  Future<void> setUpTheOldWay() async {
    await store().writePassphrase(passphrase);
    await store().writeRecoveryCode(recoveryCode);
  }

  Future<CloudBackupNotifier> backup(ProviderContainer container) async {
    await container.read(cloudBackupProvider.future);

    return container.read(cloudBackupProvider.notifier);
  }

  CloudBackupState backupState(ProviderContainer container) =>
      container.read(cloudBackupProvider).requireValue;

  Future<void> joined(ProviderContainer container) async {
    await container.read(syncProvider.future);
    await eventually(
      () =>
          container.read(syncProvider).value?.lastJoin != null ||
          container.read(syncProvider).value?.error != null,
      reason: 'the join never reported back',
    );
    expect(container.read(syncProvider).requireValue.error, isNull);
    await container.read(syncProvider.notifier).syncNow();
  }

  Future<List<String>> hosts(_Device device) async =>
      (await device.db.select(device.db.hosts).get()).map((h) => h.id).toList();

  /// Hands the key from the device awake now to whoever scans its code.
  Future<Uint8List> handedOver(ProviderContainer giver) async {
    final handoffs = DeviceHandoffService(
      api: HandoffApi(
        client: ApiClient(
          transport: server,
          tokenProvider: () async => 'test-token',
        ),
      ),
      userId: 'user-1',
      pollInterval: const Duration(milliseconds: 10),
    );

    final key = await giver
        .read(cloudBackupProvider.notifier)
        .accountKeyForHandoff();
    final shown = await handoffs.show(gives: true);
    final giving = shown.complete(accountKey: key);
    final received = await handoffs.scan(shown.code);
    await giving;

    return received!;
  }

  /// A sync ground as a build from before the account key wrote it.
  Future<void> seedOldGround() async {
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await other.addHost('old-host');

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
        syncKey: BackupEnvelope().generateSyncKey(),
      ),
    );
  }

  test('a device joins by code and never learns the passphrase', () async {
    // The desktop was set up before the account key existed.
    var container = await desktop.wake();
    await setUpTheOldWay();
    await switchSyncOn();
    await desktop.db.addHost('desktop-host');

    await backup(container);
    await until(
      () async =>
          await store().hasAccountKey() && !await store().hasPassphrase(),
      reason: 'the desktop never moved to the account key',
    );
    await joined(container);
    expect(server.head('sync')!['schema_version'], 5);

    final key = await handedOver(container);
    await desktop.sleep();

    // The phone: signed in, sync on, nothing typed.
    container = await phone.wake();
    await switchSyncOn();
    final onPhone = await backup(container);
    expect(
      backupState(container).blocker,
      CloudBackupBlocker.needsExistingPassphrase,
    );
    expect(backupState(container).accountHasKey, isTrue);

    expect(await onPhone.adoptAccountKey(key), isNull);

    expect(backupState(container).isReady, isTrue);
    expect(await store().hasPassphrase(), isFalse);
    expect(await store().hasRecoveryCode(), isFalse);

    await joined(container);
    expect(await hosts(phone), contains('desktop-host'));

    // What the phone backs up, the desktop restores -- with no secret asked
    // for on either.
    await phone.db.addHost('phone-host');
    await onPhone.backUpNow();
    final revision = server.head('backup')!;
    expect(revision['schema_version'], 5);
    expect(revision['device_id'], 'phone');
    await phone.sleep();

    container = await desktop.wake();
    final onDesktop = await backup(container);
    await onDesktop.restore(revision: revision['revision']! as int);

    expect(backupState(container).messageIsError, isFalse);
    expect(await hosts(desktop), contains('phone-host'));
  });

  test('a device behind a master password moves once it is unlocked', () async {
    // Locked at launch, every launch: the passphrase cannot be read until the
    // user unlocks, so that is when the move has to happen.
    final container = await desktop.wake();
    await setUpTheOldWay();
    await container
        .read(vaultKeyServiceProvider)
        .configureMasterPassword('dummy-master-password');
    await container.read(vaultProvider.notifier).lock();

    await backup(container);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.accountKeyRecord, isNull, reason: 'nothing to read yet');

    await container
        .read(vaultProvider.notifier)
        .unlock('dummy-master-password');

    await eventually(
      () => server.accountKeyRecord != null,
      reason: 'the device never moved to the account key after unlocking',
    );
    await until(() => store().hasAccountKey());
  });

  test('after a reset in the web panel, one device starts over and another '
      'is added again without losing its data', () async {
    // Two devices syncing under the account key.
    var container = await desktop.wake();
    await switchSyncOn();
    await desktop.db.addHost('desktop-host');
    await (await backup(
      container,
    )).configure(passphrase: passphrase, recoveryCode: recoveryCode);
    await joined(container);
    final oldKey = await store().readAccountKey();
    final key = await handedOver(container);
    await desktop.sleep();

    container = await phone.wake();
    await switchSyncOn();
    expect(await (await backup(container)).adoptAccountKey(key), isNull);
    await joined(container);
    await phone.db.addHost('phone-host');
    await container.read(syncProvider.notifier).syncNow();
    await phone.sleep();

    // Everything is forgotten, and the panel's reset clears the server.
    server
      ..accountKeyRecord = null
      ..accountKeyRevision = 0
      ..operations.clear()
      ..handoffs.clear();
    server.vaults.forEach((_, revisions) => revisions.clear());

    // The desktop is told its key is no longer the account's, is removed and
    // set up again with a new passphrase.
    container = await desktop.wake();
    var onDesktop = await backup(container);
    await eventually(
      () => backupState(container).message == kAccountKeyMismatchMessage,
      reason: 'the desktop was not told its key no longer fits',
    );
    expect(
      (await container.read(syncProvider.future)).blocker,
      SyncBlocker.accountKeyMismatch,
    );

    await onDesktop.forgetOnThisDevice();
    onDesktop = await backup(container);
    expect(backupState(container).blocker, CloudBackupBlocker.notConfigured);
    await onDesktop.configure(
      passphrase: 'a brand new passphrase',
      recoveryCode: recoveryCode,
    );
    expect(await store().readAccountKey(), isNot(oldKey));

    // Joined from nothing, it writes the snapshot the account starts from.
    await joined(container);
    expect(server.head('sync')!['schema_version'], 5);
    final newKey = await handedOver(container);
    await desktop.sleep();

    // The phone: same message, removed, added again by code -- and the host
    // only it had makes it into the account.
    container = await phone.wake();
    final onPhone = await backup(container);
    await eventually(
      () => backupState(container).message == kAccountKeyMismatchMessage,
    );
    await onPhone.forgetOnThisDevice();
    await backup(container);
    expect(await onPhone.adoptAccountKey(newKey), isNull);
    await joined(container);
    expect(await hosts(phone), containsAll(['desktop-host', 'phone-host']));
    await phone.sleep();

    container = await desktop.wake();
    await backup(container);
    await joined(container);
    expect(await hosts(desktop), contains('phone-host'));
  });

  test('a key from another account is turned away', () async {
    var container = await desktop.wake();
    await backup(container);
    await container
        .read(cloudBackupProvider.notifier)
        .configure(passphrase: passphrase, recoveryCode: recoveryCode);
    await desktop.sleep();

    container = await phone.wake();
    final onPhone = await backup(container);

    expect(
      await onPhone.adoptAccountKey(AccountKeyRecord().generateKey()),
      isNotNull,
    );
    expect(await store().isConfigured(), isFalse);
    expect(
      backupState(container).blocker,
      CloudBackupBlocker.needsExistingPassphrase,
    );
  });

  test('first-time setup keeps neither secret on the device', () async {
    final container = await desktop.wake();
    final notifier = await backup(container);
    expect(backupState(container).blocker, CloudBackupBlocker.notConfigured);

    await notifier.configure(
      passphrase: passphrase,
      recoveryCode: recoveryCode,
    );

    expect(backupState(container).usesAccountKey, isTrue);
    expect(await store().hasPassphrase(), isFalse);
    expect(await store().hasRecoveryCode(), isFalse);
    expect(server.head('backup')!['schema_version'], 5);
  });

  test('the recovery code alone sets a second device up', () async {
    var container = await desktop.wake();
    await (await backup(
      container,
    )).configure(passphrase: passphrase, recoveryCode: recoveryCode);
    final desktopKey = await store().readAccountKey();
    await desktop.sleep();

    container = await phone.wake();
    final onPhone = await backup(container);

    expect(
      await onPhone.unlockExisting(
        secret: recoveryCode,
        method: BackupUnlockMethod.recoveryCode,
      ),
      isTrue,
    );
    expect(backupState(container).isReady, isTrue);
    expect(await store().readAccountKey(), desktopKey);
  });

  test('an account whose backup was deleted is still unlocked, not set up '
      'again', () async {
    // "Delete cloud backup" leaves the account syncing. A device joining
    // after that was offered first-time setup, chose a new passphrase, and
    // could then open nothing the account held.
    server.accountKeyEnabled = false;
    await phone.wake();
    await seedOldGround();
    expect(server.head('backup'), isNull);

    final container = phone.container!;
    final onPhone = await backup(container);
    expect(
      backupState(container).blocker,
      CloudBackupBlocker.needsExistingPassphrase,
    );

    await onPhone.configure(
      passphrase: 'a passphrase invented here',
      recoveryCode: recoveryCode,
    );
    expect(await store().isConfigured(), isFalse);

    expect(await onPhone.unlockExisting(secret: 'not it'), isFalse);
    expect(await onPhone.unlockExisting(secret: passphrase), isTrue);
  });

  test('a build that seals with the passphrase is refused once the account '
      'has a key', () async {
    // The desktop moved to the key. The phone is a version behind and still
    // seals the old way: it must not write over what the others can read.
    var container = await desktop.wake();
    await (await backup(
      container,
    )).configure(passphrase: passphrase, recoveryCode: recoveryCode);
    final before = server.head('backup');
    await desktop.sleep();

    container = await phone.wake();
    await setUpTheOldWay();
    server.intercept = (request) =>
        request.url.path.endsWith('/sync/account-key')
        ? FakeSyncServer.error(404, 'not_found', 'An older build never asks.')
        : null;

    final onPhone = await backup(container);
    await onPhone.backUpNow(force: true);

    expect(backupState(container).messageIsError, isTrue);
    expect(
      backupState(container).message,
      contains('envelope_version_retired'),
    );
    expect(server.head('backup'), before);
  });

  test('a device with only the key waits for an older snapshot to be '
      'rewritten, and the device that can rewrite it does', () async {
    // The account is syncing, sealed the old way. The desktop moves to the
    // key; the phone joins by code and meets a snapshot it cannot open.
    await desktop.wake();
    await seedOldGround();
    await setUpTheOldWay();
    await store().writeAccountKey(
      await _publishKey(server, passphrase: passphrase),
    );
    final key = (await store().readAccountKey())!;
    await desktop.sleep();

    var container = await phone.wake();
    await switchSyncOn();
    expect(await (await backup(container)).adoptAccountKey(key), isNull);
    expect(
      (await container.read(syncProvider.future)).blocker,
      SyncBlocker.groundNeedsUpdate,
    );
    await phone.sleep();

    // The desktop still has the passphrase, so it opens the old snapshot,
    // joins from it, and writes the one the phone needs.
    container = await desktop.wake();
    await switchSyncOn();
    await backup(container);
    await joined(container);
    await eventually(
      () => server.head('sync')!['schema_version'] == 5,
      reason: 'the snapshot was not rewritten for the account key',
    );
    await desktop.sleep();

    container = await phone.wake();
    await joined(container);
    expect(await hosts(phone), contains('old-host'));
  });
}

/// Gives the account a key record, as a device that just moved to the key
/// would have, and returns the key.
Future<Uint8List> _publishKey(
  FakeSyncServer server, {
  required String passphrase,
}) async {
  final records = AccountKeyRecord(crypto: fastEncryptionEngine());
  final key = records.generateKey();
  server
    ..accountKeyRecord = await records.build(
      accountKey: key,
      passphrase: passphrase,
    )
    ..accountKeyRevision = 1;

  return key;
}

/// Polls an asynchronous [condition] until it holds.
Future<void> until(Future<bool> Function() condition, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(reason ?? 'condition not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// One device of the account: its own keychain, database and app.
///
/// The mock keychain is one map for the whole process, so only one device is
/// awake at a time and each keeps its own copy while the other runs.
final class _Device {
  _Device(this.id, this.server) : db = AppDatabase(NativeDatabase.memory());

  final String id;
  final FakeSyncServer server;
  final AppDatabase db;

  Map<String, String> _keychain = {};
  ProviderContainer? container;

  Future<ProviderContainer> wake() async {
    FlutterSecureStorage.setMockInitialValues(_keychain);

    return container = signedInContainer(db: db, server: server, deviceId: id);
  }

  Future<void> sleep() async {
    // Let whatever the notifiers started in the background finish writing
    // before the keychain is put away.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    container?.dispose();
    container = null;
    _keychain = await const FlutterSecureStorage().readAll();
  }
}

extension on AppDatabase {
  Future<void> addHost(String id) => hostsDao.insertHost(
    HostsCompanion.insert(
      id: id,
      workspaceId: 'default',
      label: id,
      hostname: '$id.example.com',
      createdAt: DateTime.now(),
    ),
  );
}
