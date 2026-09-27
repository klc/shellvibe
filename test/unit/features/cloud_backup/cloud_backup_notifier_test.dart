import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_transport.dart';
import 'package:shellvibe/core/sync/backup_envelope.dart';
import 'package:shellvibe/core/sync/backup_scope_store.dart';
import 'package:shellvibe/core/sync/sync_journal.dart';
import 'package:shellvibe/features/cloud_backup/data/cloud_backup_store.dart';
import 'package:shellvibe/features/cloud_backup/presentation/notifiers/cloud_backup_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

import '../../../support/fake_sync_server.dart';
import '../../../support/signed_in_container.dart';

/// The rules the cloud backup notifier adds on top of the backup service:
/// when a scheduled backup counts as taken, what setup does offline, and
/// which revision an upload claims to build on.
///
/// Driven end to end: a signed-in device, the real stores and services, and
/// an in-memory server that answers whatever it is asked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeSyncServer server;
  late ProviderContainer container;

  const passphrase = 'a long enough passphrase';

  CloudBackupStore store() => CloudBackupStore(storage: SecureStorageService());

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    server = FakeSyncServer();
    container = signedInContainer(db: db, server: server);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// A device that set cloud backup up earlier and last saw [lastKnown].
  Future<void> configured({int lastKnown = 0}) async {
    await store().writePassphrase(passphrase);
    await store().writeRecoveryCode(BackupEnvelope().generateRecoveryCode());
    await store().writeLastKnownRevision(lastKnown);
  }

  Future<CloudBackupNotifier> ready() async {
    await container.read(cloudBackupProvider.future);

    return container.read(cloudBackupProvider.notifier);
  }

  CloudBackupState current() =>
      container.read(cloudBackupProvider).requireValue;

  List<ApiRawRequest> uploads() => server.sent('PUT', '/sync/vault');

  group('the backup schedule', () {
    test('a device opened after its interval backs up on opening', () async {
      // There is no background task: opening the app is one of only two
      // moments a scheduled backup can run at all.
      await configured();
      await store().writeBackupFrequency(BackupFrequency.daily);

      await ready();

      await eventually(
        () =>
            server.head('backup') != null && current().lastAutoBackupAt != null,
        reason: 'no scheduled backup ran when the device opened',
      );
      expect(await store().readAutoBackupMark(), isNotNull);
    });

    test(
      'an upload the server turned away is not counted as the backup',
      () async {
        await configured();
        server.intercept = (request) => request.method == 'PUT'
            ? FakeSyncServer.error(
                429,
                'rate_limited',
                'Too many requests.',
                headers: {'retry-after': '30'},
              )
            : null;

        final notifier = await ready();
        await notifier.setFrequency(BackupFrequency.daily);
        await eventually(
          () =>
              uploads().isNotEmpty &&
              !current().busy &&
              current().messageIsError,
        );

        // Counted as taken, a weekly schedule would wait a week after one
        // throttled request, and nothing on screen would say so.
        expect(await store().readAutoBackupMark(), isNull);
        expect(current().lastAutoBackupAt, isNull);

        server.intercept = null;
        await notifier.maybeBackUpOnSchedule();
        expect(server.head('backup'), isNotNull);
        expect(await store().readAutoBackupMark(), isNotNull);
        expect(current().lastAutoBackupAt, isNotNull);
      },
    );

    test('a conflict holds the schedule until the user settles it', () async {
      await server.seedRevision('backup', 'another device wrote this');
      await configured(lastKnown: 0);

      final notifier = await ready();
      await notifier.backUpNow();
      expect(current().conflictingServerRevision, 1);

      // Every retry would seal the whole database again only to be refused,
      // and none of them can settle which device's data wins.
      final before = server.requests.length;
      await notifier.setFrequency(BackupFrequency.daily);
      await notifier.maybeBackUpOnSchedule();
      await pumpEventQueue();
      expect(server.requests, hasLength(before));

      // What held it was the conflict: cleared, the schedule tries again and
      // runs into the same newer backup.
      await notifier.refresh();
      final afterRefresh = server.requests.length;
      await notifier.maybeBackUpOnSchedule();
      expect(server.requests.length, greaterThan(afterRefresh));
      expect(current().conflictingServerRevision, 1);
    });
  });

  group('setup', () {
    test('setup that cannot reach the server stores nothing', () async {
      server.offline = true;
      final notifier = await ready();

      await notifier.configure(
        passphrase: passphrase,
        recoveryCode: BackupEnvelope().generateRecoveryCode(),
      );

      // Stored, the passphrase would mark this device configured, and its
      // next scheduled backup would go over whatever the account already
      // holds, sealed under a passphrase no other device has.
      expect(await store().readPassphrase(), isNull);
      expect(current().messageIsError, isTrue);

      server.offline = false;
      await notifier.configure(
        passphrase: passphrase,
        recoveryCode: BackupEnvelope().generateRecoveryCode(),
      );

      expect(await store().readPassphrase(), passphrase);
      expect(server.head('backup')?['revision'], 1);
    });

    test(
      'setup on an account that already has a backup uploads nothing',
      () async {
        await server.seedRevision('backup', 'the desktop backup');
        final notifier = await ready();

        await notifier.configure(
          passphrase: 'a passphrase this phone invented',
          recoveryCode: BackupEnvelope().generateRecoveryCode(),
        );

        expect(current().blocker, CloudBackupBlocker.needsExistingPassphrase);
        expect(await store().readPassphrase(), isNull);
        expect(uploads(), isEmpty);
      },
    );
  });

  group('which revision an upload builds on', () {
    test(
      'the one this device last knew, so a newer backup is not buried',
      () async {
        await server.seedRevision('backup', 'another device wrote this');
        await configured(lastKnown: 0);

        await (await ready()).backUpNow();

        // Refused before anything is sealed or sent.
        expect(current().conflictingServerRevision, 1);
        expect(uploads(), isEmpty);
        expect(server.vaults['backup'], hasLength(1));
      },
    );

    test('the current head, once this device has joined sync', () async {
      // A joined device already holds what every other device wrote, so the
      // server's head is the truth rather than a conflict to settle.
      await server.seedRevision('backup', 'another device wrote this');
      await configured(lastKnown: 0);
      await BackupScopeStore(
        storage: SecureStorageService(),
      ).writeAutoSyncEnabled(true);
      db.syncJournal = SyncJournal(db: db, deviceId: 'device-a');
      await db.syncJournal!.writeJoinState(SyncJoinState.done);

      await (await ready()).backUpNow();

      expect(current().conflictingServerRevision, isNull);
      expect(server.head('backup')?['revision'], 2);
      expect((jsonDecode(uploads().single.body!) as Map)['base_revision'], 1);
    });
  });
}
