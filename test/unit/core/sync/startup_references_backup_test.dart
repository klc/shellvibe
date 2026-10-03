import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/e2ee_cloud_sync_service.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

import '../../../support/fast_crypto.dart';

/// Startup snippets and on-open runbooks cross a backup restore, even though
/// hosts are restored before the snippets they point at.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('startup snippets and on-open runbooks survive a restore', () async {
    await source.snippetsDao.insertSnippet(
      SnippetsCompanion.insert(
        id: 'sn',
        workspaceId: 'default',
        title: 'Greet',
        code: 'echo hi',
      ),
    );
    await source.runbooksDao.insertRunbook(
      RunbooksCompanion.insert(
        id: 'rb',
        workspaceId: 'default',
        title: 'Check',
        createdAt: DateTime(2026),
      ),
    );
    await source.hostsDao.insertHost(
      HostsCompanion.insert(
        id: 'h',
        workspaceId: 'default',
        label: 'web',
        hostname: 'web.example.com',
        createdAt: DateTime(2026),
        startupSnippetId: const Value('sn'),
      ),
    );
    await source.templatesDao.insertTemplate(
      TemplatesCompanion.insert(
        id: 't',
        workspaceId: 'default',
        name: 'Layout',
        createdAt: DateTime(2026),
        onOpenRunbookId: const Value('rb'),
        onOpenConfirm: const Value(false),
      ),
    );
    await source.templatesDao.replacePanes('t', [
      TemplatePanesCompanion.insert(
        id: 'p',
        templateId: 't',
        paneOrder: 0,
        sessionType: 'ssh',
        hostId: const Value('h'),
        startupSnippetId: const Value('sn'),
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

    expect(
      (await target.select(target.hosts).get()).single.startupSnippetId,
      'sn',
    );
    final template = (await target.select(target.templates).get()).single;
    expect(template.onOpenRunbookId, 'rb');
    expect(template.onOpenConfirm, isFalse);
    expect(
      (await target.select(target.templatePanes).get()).single.startupSnippetId,
      'sn',
    );
  });

  test('v18 fields survive a restore: variables, tags, step kinds', () async {
    await source.snippetsDao.insertSnippet(
      SnippetsCompanion.insert(
        id: 'sn',
        workspaceId: 'default',
        title: 'Greet',
        code: r'echo ${INPUT:who}',
        variables: const Value('[{"name":"who","type":"secret"}]'),
      ),
    );
    await source.runbooksDao.insertRunbook(
      RunbooksCompanion.insert(
        id: 'rb',
        workspaceId: 'default',
        title: 'R',
        createdAt: DateTime(2026),
        tags: const Value('["ops"]'),
        variables: const Value(
          '[{"name":"env","type":"enum","options":["a"]}]',
        ),
      ),
    );
    await source.runbooksDao.replaceSteps('rb', [
      RunbookStepsCompanion.insert(
        id: 's1',
        runbookId: 'rb',
        stepOrder: 1,
        command: '# snippet: Greet',
        kind: const Value('snippet'),
        snippetId: const Value('sn'),
      ),
      RunbookStepsCompanion.insert(
        id: 's2',
        runbookId: 'rb',
        stepOrder: 2,
        command: 'Check',
        kind: const Value('approval'),
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

    expect(
      (await target.select(target.snippets).get()).single.variables,
      '[{"name":"who","type":"secret"}]',
    );
    final runbook = (await target.select(target.runbooks).get()).single;
    expect(runbook.tags, '["ops"]');
    expect(runbook.variables, contains('"env"'));
    final steps = await target.select(target.runbookSteps).get();
    expect(steps.firstWhere((s) => s.id == 's1').kind, 'snippet');
    expect(steps.firstWhere((s) => s.id == 's1').snippetId, 'sn');
    expect(steps.firstWhere((s) => s.id == 's2').kind, 'approval');
  });
}
