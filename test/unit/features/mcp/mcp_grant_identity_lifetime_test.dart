import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/features/mcp/data/mcp_server_controller.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_client_repository.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_grant_repository.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/shared/database/app_database.dart';

/// Lifetimes of "this session" grants and of client identities.
void main() {
  late AppDatabase db;
  late McpGrantRepository grants;
  late McpClientRepository clients;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    grants = McpGrantRepository(db.mcpDao);
    clients = McpClientRepository(db.mcpDao);
    for (final ws in ['ws-a', 'ws-b']) {
      await db.workspacesDao.insertWorkspace(
        WorkspacesCompanion.insert(id: ws, name: ws, createdAt: DateTime(2026)),
      );
    }
    for (final host in ['host-1', 'host-2']) {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: host,
          workspaceId: 'ws-a',
          label: host,
          hostname: '$host.example.test',
          createdAt: DateTime(2026),
        ),
      );
    }
    await db.mcpDao.insertClient(
      McpClientsCompanion.insert(
        id: 'client-1',
        workspaceId: 'ws-a',
        name: 'Agent',
        tokenHash: 'hash-1',
        createdAt: DateTime(2026),
      ),
    );
  });

  tearDown(() => db.close());

  group('session-scoped grants', () {
    Future<void> grantBoth() async {
      await grants.grant(
        clientId: 'client-1',
        hostId: 'host-1',
        mode: McpAccessMode.readonly,
        connectionScopeId: 'scope-1',
      );
      await grants.grant(
        clientId: 'client-1',
        hostId: 'host-2',
        mode: McpAccessMode.readonly,
      );
    }

    test('end with their connection; always grants stay', () async {
      await grantBoth();
      await grants.revokeByConnectionScope('scope-1');

      expect(await grants.effectiveMode('client-1', 'host-1'), isNull);
      expect(
        await grants.effectiveMode('client-1', 'host-2'),
        McpAccessMode.readonly,
      );
    });

    test('all end when the server starts again', () async {
      await grantBoth();
      await grants.revokeSessionScoped();

      expect(await grants.effectiveMode('client-1', 'host-1'), isNull);
      expect(
        await grants.effectiveMode('client-1', 'host-2'),
        McpAccessMode.readonly,
      );
    });
  });

  group('client identity', () {
    test(
      'a revoked token is recognised as revoked, an unknown one is not',
      () async {
        final (id, token) = await clients.createClient(
          workspaceId: 'ws-a',
          name: 'Agent 2',
        );
        expect(await clients.isRevoked(token), isFalse);

        await clients.revokeClient(id);
        expect(await clients.isRevoked(token), isTrue);
        expect(await clients.isRevoked('not-a-token'), isFalse);
      },
    );

    test('system client rows are found in every workspace', () async {
      for (final ws in ['ws-a', 'ws-b']) {
        await clients.createClient(
          workspaceId: ws,
          name: McpServerController.systemClientName,
        );
      }

      final rows = await clients.listClientsNamed(
        McpServerController.systemClientName,
      );
      expect(rows.map((c) => c.workspaceId), unorderedEquals(['ws-a', 'ws-b']));
    });
  });
}
