import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/data/repositories/hosts_repository.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_grant_repository.dart';
import 'package:shellvibe/features/mcp/data/tools/discovery_tools.dart';
import 'package:shellvibe/features/mcp/data/tools/mcp_tool_handler.dart';
import 'package:shellvibe/shared/database/app_database.dart';

void main() {
  late AppDatabase db;
  late ListHostsTool tool;

  const ctx = McpToolContext(
    clientId: 'client-1',
    clientName: 'Claude Code',
    // Deliberately not the workspace the app happens to be showing: a token
    // is pinned to the workspace it was issued in.
    workspaceId: 'novus',
    connectionScopeId: 'scope-1',
  );

  Future<void> insertHost({
    required String id,
    required String workspaceId,
    bool mcpVisible = true,
  }) => db.hostsDao.insertHost(
    HostsCompanion.insert(
      id: id,
      workspaceId: workspaceId,
      label: id,
      hostname: '$id.example.test',
      createdAt: DateTime.now(),
      mcpVisible: Value(mcpVisible),
    ),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    for (final (id, name) in [
      ('default', 'Default Workspace'),
      ('novus', 'Novus'),
    ]) {
      await db.workspacesDao.insertWorkspace(
        WorkspacesCompanion.insert(
          id: id,
          name: name,
          createdAt: DateTime.now(),
        ),
      );
    }
    tool = ListHostsTool(
      hostsRepository: HostsRepository(hostsDao: db.hostsDao),
      hostsDao: db.hostsDao,
      grantRepository: McpGrantRepository(db.mcpDao),
      workspacesDao: db.workspacesDao,
    );
  });

  tearDown(() async => db.close());

  test('names the workspace the token is bound to', () async {
    final result =
        await tool.execute(ctx, const {}) as Map<String, Object?>;

    expect(result['workspace'], {'id': 'novus', 'name': 'Novus'});
  });

  test('lists only that workspace, not whatever the app is showing', () async {
    await insertHost(id: 'nfs-dev', workspaceId: 'novus');
    await insertHost(id: 'mk-contabo', workspaceId: 'default');

    final result =
        await tool.execute(ctx, const {}) as Map<String, Object?>;
    final hosts = (result['hosts'] as List).cast<Map<String, Object?>>();

    expect(hosts.map((h) => h['id']), ['nfs-dev']);
  });

  test('still hides a host its owner marked invisible to agents', () async {
    await insertHost(id: 'nfs-dev', workspaceId: 'novus');
    await insertHost(id: 'secret', workspaceId: 'novus', mcpVisible: false);

    final result =
        await tool.execute(ctx, const {}) as Map<String, Object?>;
    final hosts = (result['hosts'] as List).cast<Map<String, Object?>>();

    expect(hosts.map((h) => h['id']), ['nfs-dev']);
  });

  test('falls back to the workspace id when the row is gone', () async {
    const orphan = McpToolContext(
      clientId: 'client-1',
      clientName: 'Claude Code',
      workspaceId: 'deleted-workspace',
      connectionScopeId: 'scope-1',
    );

    final result =
        await tool.execute(orphan, const {}) as Map<String, Object?>;

    expect(result['workspace'], {
      'id': 'deleted-workspace',
      'name': 'deleted-workspace',
    });
  });
}
