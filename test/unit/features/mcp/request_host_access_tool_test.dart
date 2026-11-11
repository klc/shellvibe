import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/data/repositories/hosts_repository.dart';
import 'package:shellvibe/features/mcp/data/mcp_host_connector.dart';
import 'package:shellvibe/features/mcp/data/mcp_session_pool.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_audit_repository.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_grant_repository.dart';
import 'package:shellvibe/features/mcp/data/tools/discovery_tools.dart';
import 'package:shellvibe/features/mcp/data/tools/mcp_tool_handler.dart';
import 'package:shellvibe/features/mcp/data/tools/session_tools.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_models.dart';
import 'package:shellvibe/features/mcp/domain/services/approval_coordinator.dart';
import 'package:shellvibe/shared/database/app_database.dart';

/// Fails every connection attempt.
class _NoConnector implements McpHostConnector {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Denies every candidate, like a Deny click or an unanswered prompt.
class _DenyAll extends ApprovalCoordinator {
  _DenyAll([this.reason = 'timeout']);

  final String reason;

  @override
  Future<HostAccessResult> requestHostAccess(
    HostAccessRequest request, {
    Duration timeout = const Duration(seconds: 120),
  }) async => HostAccessResult(
    granted: const [],
    denied: [
      for (final c in request.candidates)
        HostAccessDenial(hostId: c.hostId, reason: reason),
    ],
  );
}

/// Approves every candidate at [mode], whatever the window offered.
class _ApproveAs extends ApprovalCoordinator {
  _ApproveAs(this.mode);

  final McpAccessMode mode;
  final requests = <HostAccessRequest>[];

  @override
  Future<HostAccessResult> requestHostAccess(
    HostAccessRequest request, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    requests.add(request);
    return HostAccessResult(
      granted: [
        for (final c in request.candidates)
          HostAccessGrant(hostId: c.hostId, mode: mode),
      ],
      denied: const [],
    );
  }
}

void main() {
  late AppDatabase db;
  late McpGrantRepository grants;
  late McpAuditRepository audit;

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
    audit = McpAuditRepository(db.mcpDao);
  });

  tearDown(() => db.close());

  Future<Map<String?, String>> auditedDecisions(String tool) async => {
    for (final row in await audit.query())
      if (row.tool == tool) row.hostId: row.decision,
  };

  test('every host in a request is audited with how it was answered', () async {
    final tool = RequestHostAccessTool(
      hostsRepository: HostsRepository(hostsDao: db.hostsDao),
      hostsDao: db.hostsDao,
      grantRepository: grants,
      approvalCoordinator: _ApproveAs(McpAccessMode.readonly),
      auditRepository: audit,
    );

    await tool.execute(ctx, {
      'hostIds': ['host-a', 'ghost'],
      'reason': 'check disk',
    });
    // A repeat is answered from the live grant, without a window.
    await tool.execute(ctx, {
      'hostIds': ['host-a'],
      'reason': 'again',
    });

    final rows = await audit.query();
    expect(
      rows.map((r) => (r.hostId, r.decision)),
      unorderedEquals([
        ('host-a', 'confirmed'),
        ('ghost', 'auto_denied'),
        ('host-a', 'allowed'),
      ]),
    );
    final confirmed = rows.singleWhere((r) => r.decision == 'confirmed');
    expect(confirmed.hostLabel, 'host-a');
    expect(confirmed.argsJson, contains('check disk'));
  });

  test('a denied request is audited as denied', () async {
    final tool = RequestHostAccessTool(
      hostsRepository: HostsRepository(hostsDao: db.hostsDao),
      hostsDao: db.hostsDao,
      grantRepository: grants,
      approvalCoordinator: _DenyAll(),
      auditRepository: audit,
    );

    await tool.execute(ctx, {
      'hostIds': ['host-a'],
      'reason': 'deploy',
    });

    expect(await auditedDecisions('request_host_access'), {'host-a': 'denied'});
  });

  group('open_session', () {
    late McpSessionPool pool;

    setUp(() {
      pool = McpSessionPool(connector: _NoConnector());
      addTearDown(pool.dispose);
    });

    OpenSessionTool openTool() => OpenSessionTool(
      sessionPool: pool,
      hostsRepository: HostsRepository(hostsDao: db.hostsDao),
      hostsDao: db.hostsDao,
      grantRepository: grants,
      auditRepository: audit,
    );

    test('a session without a grant is audited as auto-denied', () async {
      await expectLater(
        openTool().execute(ctx, {'hostId': 'host-a'}),
        throwsA(isA<McpToolException>()),
      );

      expect(await auditedDecisions('open_session'), {'host-a': 'auto_denied'});
    });

    test('a session that fails to connect is audited as an error', () async {
      await grants.grant(
        clientId: 'client-1',
        hostId: 'host-a',
        mode: McpAccessMode.readonly,
      );

      await expectLater(
        openTool().execute(ctx, {'hostId': 'host-a'}),
        throwsA(anything),
      );

      expect(await auditedDecisions('open_session'), {'host-a': 'error'});
    });
  });

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
      auditRepository: audit,
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

  for (final (reason, cools) in [
    ('user_denied', true),
    ('timeout', false),
    ('cancelled', false),
  ]) {
    test('a "$reason" denial ${cools ? 'starts' : 'does not start'} a '
        'cooldown', () async {
      final tool = RequestHostAccessTool(
        hostsRepository: HostsRepository(hostsDao: db.hostsDao),
        hostsDao: db.hostsDao,
        grantRepository: grants,
        approvalCoordinator: _DenyAll(reason),
        auditRepository: audit,
      );

      await tool.execute(ctx, {
        'hostIds': ['host-a'],
        'reason': 'check',
      });

      expect(await grants.isInCooldown('client-1', 'host-a'), cools);
    });
  }

  test('nothing is granted above a host\'s max access', () async {
    await (db.update(db.hosts)..where((h) => h.id.equals('host-a'))).write(
      const HostsCompanion(mcpDefaultMode: Value('readonly')),
    );
    final coordinator = _ApproveAs(McpAccessMode.autonomous);
    final tool = RequestHostAccessTool(
      hostsRepository: HostsRepository(hostsDao: db.hostsDao),
      hostsDao: db.hostsDao,
      grantRepository: grants,
      approvalCoordinator: coordinator,
      auditRepository: audit,
    );

    final result =
        await tool.execute(ctx, {
              'hostIds': ['host-a'],
              'reason': 'deploy',
              'requestedMode': 'autonomous',
            })
            as Map<String, Object?>;

    final candidate = coordinator.requests.single.candidates.single;
    expect(candidate.suggestedMode, McpAccessMode.readonly);
    expect(candidate.maxMode, McpAccessMode.readonly);
    expect(result['granted'], [
      {'hostId': 'host-a', 'mode': 'readonly'},
    ]);
    expect(
      await grants.effectiveMode('client-1', 'host-a'),
      McpAccessMode.readonly,
    );
  });
}
