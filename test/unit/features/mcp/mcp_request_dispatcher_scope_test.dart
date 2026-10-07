import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/features/mcp/data/mcp_request_dispatcher.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_approval_repository.dart';
import 'package:shellvibe/features/mcp/data/tools/mcp_tool_registry.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/shared/database/app_database.dart';

/// [McpRequestDispatcher.endAllScopes] is what a server stop uses to end
/// every "this session" approval: nothing may survive a restart.
void main() {
  late AppDatabase db;
  late McpApprovalRepository approvals;
  late McpRequestDispatcher dispatcher;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    approvals = McpApprovalRepository(db.mcpDao);
    dispatcher = McpRequestDispatcher(
      registry: McpToolRegistry(const []),
      lookupClient: (_) async => (name: 'Agent', workspaceId: 'default'),
      // Same wiring as the production provider.
      onScopeEnded: approvals.revokeByConnectionScope,
    );
    await db.hostsDao.insertHost(
      HostsCompanion.insert(
        id: 'host-1',
        workspaceId: 'default',
        label: 'Host 1',
        hostname: '10.0.0.1',
        createdAt: DateTime.now(),
      ),
    );
    for (final id in ['client-1', 'client-2']) {
      await db.mcpDao.insertClient(
        McpClientsCompanion.insert(
          id: id,
          workspaceId: 'default',
          name: id,
          tokenHash: 'hash-$id',
          createdAt: DateTime.now(),
        ),
      );
    }
  });

  tearDown(() => db.close());

  Future<bool> approved(String clientId, String scope) => approvals.hasApproval(
    clientId: clientId,
    hostId: 'host-1',
    cwd: '/tmp',
    command: 'systemctl restart api',
    connectionScopeId: scope,
  );

  test('ending all scopes drops every client\'s session approvals', () async {
    final scopes = {
      for (final id in ['client-1', 'client-2'])
        id: dispatcher.connectionScopeFor(id),
    };
    for (final entry in scopes.entries) {
      await approvals.remember(
        clientId: entry.key,
        hostId: 'host-1',
        cwd: '/tmp',
        command: 'systemctl restart api',
        scope: ApprovalScope.session,
        connectionScopeId: entry.value,
      );
      expect(await approved(entry.key, entry.value), isTrue);
    }

    dispatcher.endAllScopes();
    // revokeByConnectionScope is fired, not awaited, by the dispatcher.
    await pumpEventQueue();

    for (final entry in scopes.entries) {
      expect(await approved(entry.key, entry.value), isFalse);
      expect(dispatcher.connectionScopeFor(entry.key), isNot(entry.value));
    }
  });

  test('ending scopes leaves always-scoped approvals alone', () async {
    final scope = dispatcher.connectionScopeFor('client-1');
    await approvals.remember(
      clientId: 'client-1',
      hostId: 'host-1',
      cwd: '/tmp',
      command: 'systemctl restart api',
      scope: ApprovalScope.always,
    );

    dispatcher.endAllScopes();
    await pumpEventQueue();

    expect(await approved('client-1', scope), isTrue);
  });
}
