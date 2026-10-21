import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/data/repositories/hosts_repository.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_grant_repository.dart';
import 'package:shellvibe/features/mcp/data/tools/discovery_tools.dart';
import 'package:shellvibe/features/mcp/data/tools/mcp_tool_handler.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_models.dart';
import 'package:shellvibe/features/mcp/domain/services/approval_coordinator.dart';
import 'package:shellvibe/shared/database/app_database.dart';

/// Denies every candidate, like a Deny click or an unanswered prompt.
class _DenyAll extends ApprovalCoordinator {
  @override
  Future<HostAccessResult> requestHostAccess(
    HostAccessRequest request, {
    Duration timeout = const Duration(seconds: 120),
  }) async => HostAccessResult(
    granted: const [],
    denied: [
      for (final c in request.candidates)
        HostAccessDenial(hostId: c.hostId, reason: 'timeout'),
    ],
  );
}

void main() {
  late AppDatabase db;
  late McpGrantRepository grants;

  const ctx = McpToolContext(
    clientId: 'client-1',
    clientName: 'Agent',
    workspaceId: 'default',
    connectionScopeId: 'scope-1',
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'default',
        name: 'Default',
        createdAt: DateTime.now(),
      ),
    );
    await db.mcpDao.insertClient(
      McpClientsCompanion.insert(
        id: 'client-1',
        workspaceId: 'default',
        name: 'Agent',
        tokenHash: 'hash-1',
        createdAt: DateTime.now(),
      ),
    );
    await db.hostsDao.insertHost(
      HostsCompanion.insert(
        id: 'host-a',
        workspaceId: 'default',
        label: 'host-a',
        hostname: 'a.example.test',
        createdAt: DateTime.now(),
      ),
    );
    grants = McpGrantRepository(db.mcpDao);
  });

  tearDown(() => db.close());

  test('a repeat request for a granted host keeps the grant live', () async {
    await grants.grant(
      clientId: 'client-1',
      hostId: 'host-a',
      mode: McpAccessMode.guarded,
    );
    final tool = RequestHostAccessTool(
      hostsRepository: HostsRepository(hostsDao: db.hostsDao),
      hostsDao: db.hostsDao,
      grantRepository: grants,
      approvalCoordinator: _DenyAll(),
    );

    final result =
        await tool.execute(ctx, {
              'hostIds': ['host-a'],
              'reason': 'again',
            })
            as Map<String, Object?>;

    expect(await grants.effectiveMode('client-1', 'host-a'), isNotNull);
    expect(result['granted'], [
      {'hostId': 'host-a', 'mode': 'guarded'},
    ]);
    expect(result['denied'], isEmpty);
  });
}
