import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/e2ee_cloud_sync_service.dart';
import 'package:shellvibe/core/sync/sync_journal.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

import '../../../support/fast_crypto.dart';

/// What a restore does to the rows already on the device it lands on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase source;
  late AppDatabase target;
  late VaultKeyService keys;
  late E2EECloudSyncService sync;

  const passphrase = 'restore merge passphrase';
  final created = DateTime(2026, 1, 2);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    source = AppDatabase(NativeDatabase.memory());
    target = AppDatabase(NativeDatabase.memory());

    keys = VaultKeyService(
      encryptionEngine: fastEncryptionEngine(),
      secureStorageService: SecureStorageService(),
    );
    await keys.getDek();

    sync = E2EECloudSyncService(
      vaultKeyService: keys,
      cryptoEngine: fastEncryptionEngine(),
    );
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  Future<void> addRunbook(
    AppDatabase db,
    String id, {
    String title = 'Deploy',
    String? variables,
  }) => db
      .into(db.runbooks)
      .insert(
        RunbooksCompanion.insert(
          id: id,
          workspaceId: 'default',
          title: title,
          createdAt: created,
          variables: Value(variables),
          tags: const Value('["prod"]'),
        ),
      );

  Future<void> addStep(AppDatabase db, String id, String runbookId) => db
      .into(db.runbookSteps)
      .insert(
        RunbookStepsCompanion.insert(
          id: id,
          runbookId: runbookId,
          stepOrder: 0,
          command: 'echo $id',
        ),
      );

  Future<void> addHost(AppDatabase db, String id) => db
      .into(db.hosts)
      .insert(
        HostsCompanion.insert(
          id: id,
          workspaceId: 'default',
          label: id,
          hostname: '$id.example.com',
          createdAt: created,
        ),
      );

  Future<BackupImportResult> restore(
    String backup, {
    bool recordAsChange = false,
  }) => sync.importEncryptedBackup(
    backupPackageJson: backup,
    db: target,
    masterPassword: passphrase,
    recordAsChange: recordAsChange,
  );

  Future<String> backupOf(AppDatabase db) =>
      sync.exportEncryptedBackup(db: db, masterPassword: passphrase);

  Future<List<String>> stepsOf(String runbookId) async => [
    for (final step in await (target.select(
      target.runbookSteps,
    )..where((s) => s.runbookId.equals(runbookId))).get())
      step.id,
  ];

  test('an older backup leaves the columns it does not know alone', () async {
    // Written by a build before runbooks had variables or tags. Restored as
    // null, it wiped them from every runbook it was restored over.
    await addRunbook(target, 'r1', variables: '[{"name":"TOKEN"}]');

    final payload = {
      'version': 3,
      'included': BackupScope.full.toManifest(),
      'workspaces': <Object?>[],
      'host_groups': <Object?>[],
      'runbooks': [
        {
          'id': 'r1',
          'workspaceId': 'default',
          'title': 'Deploy v2',
          'description': null,
          'createdAt': created.toIso8601String(),
        },
      ],
    };
    await restore(
      await sync.envelope.seal(
        payloadJson: jsonEncode(payload),
        dek: await keys.getDek(),
        passphrase: passphrase,
      ),
    );

    final runbook = await target.select(target.runbooks).getSingle();
    expect(runbook.title, 'Deploy v2');
    expect(runbook.variables, '[{"name":"TOKEN"}]');
    expect(runbook.tags, '["prod"]');
  });

  group('children of a restored row', () {
    test('a runbook comes back with the backup\'s steps, not both', () async {
      // An edit replaces a runbook's steps under new ids. Merged with the
      // ones here, the restored runbook ran its old steps and its new ones.
      await addRunbook(source, 'r1');
      await addStep(source, 'step-old', 'r1');
      await addRunbook(target, 'r1');
      await addStep(target, 'step-new', 'r1');
      await addRunbook(target, 'r2');
      await addStep(target, 'step-elsewhere', 'r2');

      await restore(await backupOf(source));

      expect(await stepsOf('r1'), ['step-old']);
      expect(await stepsOf('r2'), [
        'step-elsewhere',
      ], reason: 'a runbook the backup does not carry is not touched');
    });

    test('a step waiting to be sent stays', () async {
      await addRunbook(source, 'r1');
      await addStep(source, 'step-old', 'r1');
      await addRunbook(target, 'r1');
      final journal = SyncJournal(db: target, deviceId: 'target-device');
      target.syncJournal = journal;
      await journal.upsert(
        entityType: 'runbook_steps',
        entityId: 'step-unsent',
        write: () => addStep(target, 'step-unsent', 'r1'),
      );

      await restore(await backupOf(source));

      expect(await stepsOf('r1'), containsAll(['step-old', 'step-unsent']));
    });
  });

  group('on a device that has joined sync', () {
    late SyncJournal journal;

    setUp(() async {
      journal = SyncJournal(db: target, deviceId: 'target-device');
      target.syncJournal = journal;
      await journal.writeJoinState(SyncJoinState.done);
    });

    Future<Set<String>> outbox() async => {
      for (final o in await journal.pending())
        '${o.operation} ${o.entityType}/${o.entityId}',
    };

    test('what a restore changed goes out as this device\'s edits', () async {
      // Written straight to the database, a restored file never reached
      // the other devices, and a row it overwrote kept the version of what
      // it replaced: one version, two contents.
      await addHost(source, 'h-new');
      await addHost(source, 'h-same');
      await addRunbook(source, 'r1');
      await addStep(source, 'step-old', 'r1');
      await addHost(target, 'h-same');
      await addRunbook(target, 'r1');
      await addStep(target, 'step-new', 'r1');

      await restore(await backupOf(source), recordAsChange: true);

      final sent = await outbox();
      expect(sent, contains('upsert hosts/h-new'));
      expect(sent, contains('upsert runbook_steps/step-old'));
      expect(sent, contains('delete runbook_steps/step-new'));
      expect(
        sent,
        isNot(contains('upsert hosts/h-same')),
        reason: 'a row that came back as it was is not news',
      );
    });

    test('a sync ground is not recorded', () async {
      await addHost(source, 'h-new');

      await restore(await backupOf(source));

      expect(await journal.pending(), isEmpty);
    });
  });
}
