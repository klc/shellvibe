import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/sync_journal.dart';
import 'package:shellvibe/shared/database/app_database.dart';

/// A write that forgets to record is a change that silently never syncs, and
/// nothing later in the pipeline can notice. So the journal is attached to the
/// database and every DAO write goes through it -- which is only true if the
/// DAOs actually call it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    db.syncJournal = SyncJournal(db: db);
  });

  tearDown(() => db.close());

  Future<List<String>> recorded() async {
    final pending = await SyncJournal(db: db).pending();

    return pending
        .map((o) => '${o.entityType}/${o.entityId}:${o.operation}')
        .toList();
  }

  test('no journal means no recording, and no failure', () async {
    // The path a device without cloud backup takes. It must not need a
    // different DAO.
    db.syncJournal = null;

    await db.hostsDao.insertHost(
      HostsCompanion.insert(
        id: 'h1',
        workspaceId: 'default',
        label: 'web',
        hostname: 'web.example.com',
        createdAt: DateTime.now(),
      ),
    );

    expect(await db.select(db.hosts).get(), hasLength(1));
    expect(await recorded(), isEmpty);
  });

  test('every mutating DAO records its row', () async {
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'ws',
        name: 'Work',
        createdAt: DateTime.now(),
      ),
    );
    await db.identitiesDao.insertIdentity(
      IdentitiesCompanion.insert(
        id: 'i1',
        workspaceId: 'ws',
        title: 'key',
        username: 'deploy',
        authType: 'key',
        createdAt: DateTime.now(),
      ),
    );
    await db.hostsDao.insertHostGroup(
      HostGroupsCompanion.insert(id: 'g1', workspaceId: 'ws', name: 'Prod'),
    );
    await db.hostsDao.insertHost(
      HostsCompanion.insert(
        id: 'h1',
        workspaceId: 'ws',
        label: 'web',
        hostname: 'web.example.com',
        createdAt: DateTime.now(),
      ),
    );
    await db.tunnelsDao.insertRule(
      PortForwardRulesCompanion.insert(
        id: 'p1',
        hostId: 'h1',
        type: 'local',
        localPort: 8080,
      ),
    );
    await db.snippetsDao.insertSnippet(
      SnippetsCompanion.insert(
        id: 's1',
        workspaceId: 'ws',
        title: 'tail',
        code: 'tail -f',
      ),
    );
    await db.runbooksDao.insertRunbook(
      RunbooksCompanion.insert(
        id: 'r1',
        workspaceId: 'ws',
        title: 'Deploy',
        createdAt: DateTime.now(),
      ),
    );
    await db.runbooksDao.replaceSteps('r1', [
      RunbookStepsCompanion.insert(
        id: 'rs1',
        runbookId: 'r1',
        stepOrder: 0,
        command: 'echo',
      ),
    ]);
    await db.templatesDao.insertTemplate(
      TemplatesCompanion.insert(
        id: 't1',
        workspaceId: 'ws',
        name: 'Two panes',
        createdAt: DateTime.now(),
      ),
    );
    await db.templatesDao.replacePanes('t1', [
      TemplatePanesCompanion.insert(
        id: 'tp1',
        templateId: 't1',
        paneOrder: 0,
        sessionType: 'ssh',
      ),
    ]);
    await db.bookmarksDao.insertBookmark(
      BookmarksCompanion.insert(
        id: 'b1',
        workspaceId: 'ws',
        createdAt: DateTime.now(),
      ),
    );

    expect(
      await recorded(),
      containsAll([
        'workspaces/ws:upsert',
        'identities/i1:upsert',
        'host_groups/g1:upsert',
        'hosts/h1:upsert',
        'port_forward_rules/p1:upsert',
        'snippets/s1:upsert',
        'runbooks/r1:upsert',
        'runbook_steps/rs1:upsert',
        'templates/t1:upsert',
        'template_panes/tp1:upsert',
        'bookmarks/b1:upsert',
      ]),
    );
  });

  test('a bulk identity assignment records one operation per host', () async {
    // A single UPDATE statement, but the log is keyed by row: recording
    // nothing would leave every other device pointing at the old identity.
    for (final id in ['h1', 'h2']) {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: id,
          workspaceId: 'default',
          label: id,
          hostname: '$id.example.com',
          createdAt: DateTime.now(),
        ),
      );
    }
    await db.identitiesDao.insertIdentity(
      IdentitiesCompanion.insert(
        id: 'i1',
        workspaceId: 'default',
        title: 'key',
        username: 'deploy',
        authType: 'key',
        createdAt: DateTime.now(),
      ),
    );
    await SyncJournal(db: db).clearSent(await SyncJournal(db: db).pending());

    await db.hostsDao.assignIdentityToHosts(['h1', 'h2'], 'i1');

    expect(
      await recorded(),
      containsAll(['hosts/h1:upsert', 'hosts/h2:upsert']),
    );
  });

  test('deleting a template records the panes the database removes', () async {
    // The DAO no longer deletes the panes by hand. The cascade does it, and
    // the journal is what tells the other devices.
    await db.templatesDao.insertTemplate(
      TemplatesCompanion.insert(
        id: 't1',
        workspaceId: 'default',
        name: 'Two panes',
        createdAt: DateTime.now(),
      ),
    );
    await db.templatesDao.replacePanes('t1', [
      TemplatePanesCompanion.insert(
        id: 'tp1',
        templateId: 't1',
        paneOrder: 0,
        sessionType: 'ssh',
      ),
    ]);
    await SyncJournal(db: db).clearSent(await SyncJournal(db: db).pending());

    await db.templatesDao.deleteTemplate('t1');

    expect(
      await recorded(),
      containsAll(['templates/t1:delete', 'template_panes/tp1:delete']),
    );
    expect(await db.select(db.templatePanes).get(), isEmpty);
  });
}
