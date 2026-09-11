import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/workspaces/data/repositories/workspace_repository.dart';
import 'package:shellvibe/shared/database/app_database.dart';

void main() {
  late AppDatabase db;
  late WorkspaceRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = WorkspaceRepository(db.workspacesDao);
  });

  tearDown(() async {
    await db.close();
  });

  test('seeds only the protected default workspace', () async {
    final workspaces = await repository.getWorkspaces();

    expect(workspaces, hasLength(1));
    expect(workspaces.single.id, 'default');
    expect(workspaces.single.name, 'Default Workspace');
  });

  test('creates and renames workspaces with normalized unique names', () async {
    final created = await repository.createWorkspace('  Client Ops  ');
    final createdAt = created.createdAt;

    expect(created.name, 'Client Ops');
    expect(
      repository.createWorkspace('client ops'),
      throwsA(isA<StateError>()),
    );
    expect(repository.createWorkspace('   '), throwsA(isA<ArgumentError>()));

    await repository.renameWorkspace(created.id, '  Client Production  ');
    final renamed = (await repository.getWorkspaces()).singleWhere(
      (workspace) => workspace.id == created.id,
    );

    expect(renamed.name, 'Client Production');
    expect(renamed.createdAt, createdAt);
  });

  test('protects default and reports workspace-owned records', () async {
    expect(repository.deleteWorkspace('default'), throwsA(isA<StateError>()));

    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'client',
        name: 'Client',
        createdAt: DateTime.now(),
      ),
    );
    await db.hostsDao.insertHost(
      HostsCompanion.insert(
        id: 'host-1',
        workspaceId: 'client',
        label: 'API',
        hostname: 'api.example.test',
        createdAt: DateTime.now(),
      ),
    );
    await db.hostsDao.insertHostGroup(
      HostGroupsCompanion.insert(
        id: 'group-1',
        workspaceId: 'client',
        name: 'Production',
      ),
    );
    await db.identitiesDao.insertIdentity(
      IdentitiesCompanion.insert(
        id: 'identity-1',
        workspaceId: 'client',
        title: 'Deploy key',
        username: 'deploy',
        authType: 'key',
        createdAt: DateTime.now(),
      ),
    );
    await db.snippetsDao.insertSnippet(
      SnippetsCompanion.insert(
        id: 'snippet-1',
        workspaceId: 'client',
        title: 'Deploy',
        code: './deploy.sh',
      ),
    );
    await db.runbooksDao.insertRunbook(
      RunbooksCompanion.insert(
        id: 'runbook-1',
        workspaceId: 'client',
        title: 'Deploy',
        createdAt: DateTime.now(),
      ),
    );
    await db.tunnelsDao.insertRule(
      PortForwardRulesCompanion.insert(
        id: 'tunnel-1',
        hostId: 'host-1',
        type: 'local',
        localPort: 8080,
      ),
    );

    final usage = await repository.getUsage('client');
    expect(usage.hosts, 1);
    expect(usage.groups, 1);
    expect(usage.identities, 1);
    expect(usage.tunnels, 1);
    expect(usage.snippets, 1);
    expect(usage.runbooks, 1);

    await repository.deleteWorkspace('client');

    expect(await db.workspacesDao.getWorkspaceById('client'), isNull);
    expect(await db.hostsDao.getHostById('host-1'), isNull);
    expect(await db.identitiesDao.getIdentityById('identity-1'), isNull);
    expect(await db.tunnelsDao.getRuleById('tunnel-1'), isNull);
    expect(await db.snippetsDao.getSnippetsByWorkspace('client'), isEmpty);
    expect(await db.runbooksDao.getRunbooksByWorkspace('client'), isEmpty);
  });
}
