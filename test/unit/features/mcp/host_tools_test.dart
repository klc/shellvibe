import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/data/repositories/hosts_repository.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_audit_repository.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_grant_repository.dart';
import 'package:shellvibe/features/mcp/data/tools/host_tools.dart';
import 'package:shellvibe/features/mcp/data/tools/mcp_tool_handler.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_models.dart';
import 'package:shellvibe/features/mcp/domain/services/approval_coordinator.dart';
import 'package:shellvibe/shared/database/app_database.dart';

const _ctx = McpToolContext(
  clientId: 'client-1',
  clientName: 'Claude Code',
  workspaceId: 'ws',
  connectionScopeId: 'scope',
);

void main() {
  late AppDatabase db;
  late ApprovalCoordinator coordinator;
  late McpAuditRepository audit;
  late HostsRepository hosts;
  late AddHostTool tool;
  late int added;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    for (final ws in ['ws', 'other-ws']) {
      await db.workspacesDao.insertWorkspace(
        WorkspacesCompanion.insert(id: ws, name: ws, createdAt: DateTime(2026)),
      );
    }
    await db.mcpDao.insertClient(
      McpClientsCompanion.insert(
        id: 'client-1',
        workspaceId: 'ws',
        name: 'client-1',
        tokenHash: 'hash',
        createdAt: DateTime(2026),
      ),
    );
    for (final (id, ws, user) in [
      ('id-deploy', 'ws', 'deploy'),
      ('id-root', 'ws', 'root'),
      ('id-foreign', 'other-ws', 'deploy'),
    ]) {
      await db.identitiesDao.insertIdentity(
        IdentitiesCompanion.insert(
          id: id,
          workspaceId: ws,
          title: 'Key $id',
          username: user,
          authType: 'key',
          createdAt: DateTime(2026),
        ),
      );
    }
    coordinator = ApprovalCoordinator();
    audit = McpAuditRepository(db.mcpDao);
    hosts = HostsRepository(hostsDao: db.hostsDao);
    added = 0;
    tool = AddHostTool(
      hostsRepository: hosts,
      identitiesDao: db.identitiesDao,
      auditRepository: audit,
      approvalCoordinator: coordinator,
      onHostAdded: () => added++,
    );
  });

  tearDown(() async {
    coordinator.dispose();
    await db.close();
  });

  Future<HostAddRequest> answer(HostAddDecision decision) async {
    for (var i = 0; i < 100; i++) {
      final pending = coordinator.currentHostAdds;
      if (pending.isNotEmpty) {
        coordinator.resolveHostAdd(pending.single.id, decision);
        return pending.single.request;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('no approval was requested');
  }

  Matcher toolError(McpErrorCode code, [Object? message]) => throwsA(
    isA<McpToolException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.message, 'message', message ?? isNotEmpty),
  );

  Future<List<Map<String, Object?>>> auditRows() async => [
    for (final r in await audit.query())
      {'decision': r.decision, 'args': jsonDecode(r.argsJson)},
  ];

  Future<void> saved(
    String hostname, {
    String workspace = 'ws',
    int port = 22,
    bool visible = true,
  }) => db.hostsDao.insertHost(
    HostsCompanion.insert(
      id: 'existing-$workspace',
      workspaceId: workspace,
      label: 'old',
      hostname: hostname,
      port: Value(port),
      createdAt: DateTime(2026),
      mcpVisible: Value(visible),
    ),
  );

  group('validation, before anyone is asked', () {
    const bad = <Map<String, Object?>>[
      {'label': 'x', 'hostname': '-oProxyCommand=touch /tmp/p'},
      {'label': 'x', 'hostname': 'web 1'},
      {'label': 'x', 'hostname': r'web;rm'},
      {'label': 'x', 'hostname': 'web', 'port': 0},
      {'label': 'x', 'hostname': 'web', 'port': 70000},
      {'label': 'x', 'hostname': 'web', 'username': '-oX'},
      {'label': 'x', 'hostname': 'web', 'username': 'a b'},
      {'label': 'two\nlines', 'hostname': 'web'},
      {'label': '  ', 'hostname': 'web'},
    ];
    for (final args in bad) {
      test('refuses ${jsonEncode(args)}', () async {
        await expectLater(
          tool.execute(_ctx, args),
          toolError(McpErrorCode.internal),
        );
        expect(coordinator.currentHostAdds, isEmpty);
        final row = (await auditRows()).single;
        expect(row['decision'], 'denied');
        expect((row['args'] as Map)['rejected'], isNotEmpty);
      });
    }

    test('accepts DNS names, IPv4 and IPv6', () async {
      for (final hostname in [
        'web-1.example.com',
        '10.0.0.5',
        '::1',
        'fe80::1%en0',
      ]) {
        final future = tool.execute(_ctx, {'label': 'x', 'hostname': hostname});
        await answer(HostAddDecision.denied);
        await expectLater(future, toolError(McpErrorCode.policyDenied));
      }
    });
  });

  test('an address already saved and visible is reported, nothing asked or '
      'added', () async {
    await saved('Web.Example.com');
    final result =
        await tool.execute(_ctx, {
              'label': 'web',
              'hostname': 'web.example.com',
            })
            as Map;
    expect(result['status'], 'exists');
    expect(result['hostId'], 'existing-ws');
    expect(coordinator.currentHostAdds, isEmpty);
    expect(added, 0);
    expect((await auditRows()).single['decision'], 'allowed');
  });

  test('an address saved but hidden from agents is refused', () async {
    await saved('web.example.com', visible: false);
    await expectLater(
      tool.execute(_ctx, {'label': 'web', 'hostname': 'web.example.com'}),
      toolError(McpErrorCode.hostNotVisible, contains('hidden')),
    );
    expect((await auditRows()).single['decision'], 'denied');
  });

  test('the same hostname on another port or in another workspace is a new '
      'host', () async {
    await saved('web.example.com', port: 2222);
    await saved('web.example.com', workspace: 'other-ws');
    final future = tool.execute(_ctx, {
      'label': 'web',
      'hostname': 'web.example.com',
    });
    await answer(HostAddDecision.denied);
    await expectLater(future, toolError(McpErrorCode.policyDenied));
  });

  test('a label another visible host has is refused', () async {
    await saved('db.example.com');
    await expectLater(
      tool.execute(_ctx, {'label': 'OLD', 'hostname': 'web.example.com'}),
      toolError(McpErrorCode.internal, contains('already labelled')),
    );
    expect(coordinator.currentHostAdds, isEmpty);
  });

  test('saved meanwhile: the address is reported, not added twice', () async {
    final future = tool.execute(_ctx, {'label': 'web', 'hostname': 'web'});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await saved('web');
    await answer(const HostAddDecision(approved: true));
    final result = await future as Map;
    expect(result['status'], 'exists');
    expect(await hosts.getHostsByWorkspace('ws'), hasLength(1));
    expect(added, 0);
  });

  test(
    'no credentials attached: the agent is told it cannot connect yet',
    () async {
      final future = tool.execute(_ctx, {'label': 'web', 'hostname': 'web'});
      await answer(const HostAddDecision(approved: true));
      final result = await future as Map;
      expect(result['note'], contains('no credentials'));
      expect(result['note'], contains('HOST_KEY_UNTRUSTED'));
    },
  );

  test('denied: nothing saved, refusal logged', () async {
    final future = tool.execute(_ctx, {'label': 'web', 'hostname': 'web'});
    await answer(HostAddDecision.denied);
    await expectLater(
      future,
      toolError(McpErrorCode.policyDenied, contains('declined')),
    );
    expect(await hosts.getHostsByWorkspace('ws'), isEmpty);
    expect(added, 0);
    expect((await auditRows()).single['decision'], 'denied');
  });

  test('approved: saved with the identity the user picked, visible, not '
      'granted', () async {
    final future = tool.execute(_ctx, {
      'label': 'web-1',
      'hostname': 'web1.example.com',
      'port': 2222,
      'username': 'deploy',
    });
    final request = await answer(
      const HostAddDecision(approved: true, identityId: 'id-deploy'),
    );
    final result = await future as Map;

    expect(request.clientName, 'Claude Code');
    expect(request.hostname, 'web1.example.com');
    expect(request.port, 2222);
    expect(request.username, 'deploy');
    // This workspace's identities only.
    expect(request.identities.map((i) => i.id), ['id-deploy', 'id-root']);

    expect(result['status'], 'added');
    expect(result['note'], contains('request_host_access'));
    final host = (await hosts.getHostById(result['hostId'] as String))!;
    expect(host.workspaceId, 'ws');
    expect(host.label, 'web-1');
    expect(host.hostname, 'web1.example.com');
    expect(host.port, 2222);
    expect(host.username, 'deploy');
    expect(host.identityId, 'id-deploy');
    expect(host.mcpVisible, isTrue);
    expect(host.mcpMaxMode, 'guarded');
    expect(
      await McpGrantRepository(db.mcpDao).effectiveMode('client-1', host.id),
      isNull,
    );
    expect(added, 1);
    final row = (await auditRows()).single;
    expect(row['decision'], 'confirmed');
    expect((row['args'] as Map)['hostId'], host.id);
  });

  test('an identity of another workspace is not attached', () async {
    final future = tool.execute(_ctx, {'label': 'web', 'hostname': 'web'});
    await answer(
      const HostAddDecision(approved: true, identityId: 'id-foreign'),
    );
    final result = await future as Map;
    final host = (await hosts.getHostById(result['hostId'] as String))!;
    expect(host.identityId, isNull);
  });

  test('revoking the client refuses its pending add', () async {
    final future = tool.execute(_ctx, {'label': 'web', 'hostname': 'web'});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    coordinator.cancelForClient('client-1');
    await expectLater(future, toolError(McpErrorCode.policyDenied));
  });
}
