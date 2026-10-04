import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/e2ee_cloud_sync_service.dart';
import 'package:shellvibe/core/sync/sync_engine.dart';
import 'package:shellvibe/core/sync/sync_journal.dart';
import 'package:shellvibe/core/sync/sync_row_codec.dart';
import 'package:shellvibe/core/sync/sync_row_writer.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

import '../../../support/fast_crypto.dart';

/// Run history carries command output, which can hold secrets, in a database
/// file that is not encrypted. It must never leave the device, so every route
/// out is checked here rather than trusting that nobody adds a table to a list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const historyTables = [
    'runbook_runs',
    'runbook_run_hosts',
    'runbook_run_steps',
  ];
  const secretOutput = 'TOP-SECRET-OUTPUT-MARKER';

  late AppDatabase source;
  late AppDatabase target;
  late E2EECloudSyncService sync;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    source = AppDatabase(NativeDatabase.memory());
    target = AppDatabase(NativeDatabase.memory());
    final vaultKeyService = VaultKeyService(
      encryptionEngine: fastEncryptionEngine(),
      secureStorageService: SecureStorageService(),
    );
    await vaultKeyService.getDek();
    sync = E2EECloudSyncService(
      vaultKeyService: vaultKeyService,
      cryptoEngine: fastEncryptionEngine(),
    );
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  Future<void> seedHistory() async {
    await source.runHistoryDao.insertRun(
      RunbookRunsCompanion.insert(
        id: 'r1',
        workspaceId: 'default',
        runbookId: const Value('rb'),
        kind: 'runbook',
        title: 'Deploy',
        strategy: 'rolling',
        startedAt: DateTime(2026),
        finishedAt: DateTime(2026),
        status: 'succeeded',
      ),
      [
        RunbookRunHostsCompanion.insert(
          id: 'rh1',
          runId: 'r1',
          position: 0,
          hostId: 'h',
          hostLabel: 'web',
          status: 'succeeded',
        ),
      ],
      [
        RunbookRunStepsCompanion.insert(
          id: 'rs1',
          runHostId: 'rh1',
          stepId: 's1',
          stepOrder: 1,
          command: 'cat /etc/secret',
          status: 'success',
          output: const Value(secretOutput),
        ),
      ],
    );
  }

  test('history tables are in no sync or backup table list', () {
    for (final table in historyTables) {
      expect(SyncRowCodec.syncableTypes, isNot(contains(table)));
      expect(SyncJournal.cascades.keys, isNot(contains(table)));
      expect(SyncJournal.setNulls.keys, isNot(contains(table)));
      for (final targets in [
        ...SyncJournal.cascades.values,
        ...SyncJournal.setNulls.values,
      ]) {
        expect(targets.map((t) => t.$1), isNot(contains(table)));
      }
      for (final tables in SyncEngine.categoryTables.values) {
        expect(tables, isNot(contains(table)));
      }
      for (final category in BackupCategory.values) {
        expect(category.payloadKeys, isNot(contains(table)));
      }
    }
  });

  test('an exported backup carries no history', () async {
    await seedHistory();
    final envelope = await sync.exportEncryptedBackup(
      db: source,
      masterPassword: 'pw',
    );
    final opened = await BackupEnvelope(
      crypto: fastEncryptionEngine(),
    ).open(envelopeJson: envelope, secret: 'pw');
    final payload = jsonDecode(opened.payloadJson) as Map<String, dynamic>;

    for (final table in historyTables) {
      expect(payload.keys, isNot(contains(table)));
    }
    expect(opened.payloadJson, isNot(contains(secretOutput)));
    expect(opened.payloadJson, isNot(contains('cat /etc/secret')));
  });

  test('history writes are not journaled for sync', () async {
    await seedHistory();
    final pending = await source
        .customSelect('SELECT COUNT(*) AS n FROM pending_operations')
        .getSingle();
    expect(pending.read<int>('n'), 0);
  });

  test('default targets and step policy survive a backup round trip', () async {
    await source.runbooksDao.insertRunbook(
      RunbooksCompanion.insert(
        id: 'rb',
        workspaceId: 'default',
        title: 'Deploy',
        createdAt: DateTime(2026),
        defaultHostIds: const Value('["h1","h2"]'),
      ),
    );
    await source.runbooksDao.replaceSteps('rb', [
      RunbookStepsCompanion.insert(
        id: 's1',
        runbookId: 'rb',
        stepOrder: 1,
        command: 'uptime',
        onFailure: const Value('continue'),
        retries: const Value(3),
      ),
    ]);

    final envelope = await sync.exportEncryptedBackup(
      db: source,
      masterPassword: 'pw',
    );
    await sync.importEncryptedBackup(
      backupPackageJson: envelope,
      db: target,
      masterPassword: 'pw',
    );

    final runbook = (await target.select(target.runbooks).get()).single;
    expect(runbook.defaultHostIds, '["h1","h2"]');
    final step = (await target.select(target.runbookSteps).get()).single;
    expect(step.onFailure, 'continue');
    expect(step.retries, 3);
  });

  group('rows from an older client (fields absent)', () {
    test('the row writer applies the defaults', () async {
      await target
          .into(target.workspaces)
          .insert(
            WorkspacesCompanion.insert(
              id: 'ws',
              name: 'w',
              createdAt: DateTime(2026),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      final runbook = await SyncRowWriter.write(target, 'runbooks', {
        'id': 'rb',
        'workspaceId': 'ws',
        'title': 'Old',
        'description': null,
        'createdAt': DateTime(2026).toIso8601String(),
      });
      final step = await SyncRowWriter.write(target, 'runbook_steps', {
        'id': 's1',
        'runbookId': 'rb',
        'stepOrder': 1,
        'command': 'uptime',
      });
      expect(runbook.written, isTrue);
      expect(step.written, isTrue);

      final rb = (await target.select(target.runbooks).get()).single;
      expect(rb.defaultHostIds, isNull);
      final st = (await target.select(target.runbookSteps).get()).single;
      expect(st.onFailure, 'stop');
      expect(st.retries, 0);
      expect(st.timeoutSeconds, 30);
    });

    test(
      'unknown keys from a newer client are ignored by the writer',
      () async {
        await target
            .into(target.workspaces)
            .insert(
              WorkspacesCompanion.insert(
                id: 'ws',
                name: 'w',
                createdAt: DateTime(2026),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        final result = await SyncRowWriter.write(target, 'runbooks', {
          'id': 'rb',
          'workspaceId': 'ws',
          'title': 'New',
          'createdAt': DateTime(2026).toIso8601String(),
          'someFutureField': 'x',
        });
        expect(result.written, isTrue);
        expect(await target.select(target.runbooks).get(), hasLength(1));
      },
    );
  });
}
