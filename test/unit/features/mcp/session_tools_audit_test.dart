import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/ssh_session_manager.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/mcp/data/mcp_host_connector.dart';
import 'package:shellvibe/features/mcp/data/mcp_session_pool.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_approval_repository.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_audit_repository.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_grant_repository.dart';
import 'package:shellvibe/features/mcp/data/tools/command_tools.dart';
import 'package:shellvibe/features/mcp/data/tools/mcp_tool_handler.dart';
import 'package:shellvibe/features/mcp/data/tools/session_tools.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_models.dart';
import 'package:shellvibe/features/mcp/domain/services/approval_coordinator.dart';
import 'package:shellvibe/features/mcp/domain/services/output_redactor.dart';
import 'package:shellvibe/features/mcp/domain/services/policy_engine.dart';
import 'package:shellvibe/shared/database/app_database.dart';

import '../../core/mcp/fake_shell_channel.dart';

class _ChannelSession implements SSHSession {
  _ChannelSession(this.fake);

  final FakeShellChannel fake;

  @override
  Stream<Uint8List> get stdout => fake.stdout.map((b) => Uint8List.fromList(b));

  @override
  Stream<Uint8List> get stderr => fake.stderr.map((b) => Uint8List.fromList(b));

  @override
  Future<void> get done => fake.done;

  @override
  int? get exitCode => fake.exitStatus;

  @override
  void write(Uint8List data) => fake.write(data);

  @override
  void close() => fake.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Manager implements SSHSessionManager {
  @override
  Future<SSHSession> openExec(String command) async =>
      _ChannelSession(FakeShellChannel());

  @override
  Stream<SSHClient?> get clientChanges => const Stream.empty();

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connector implements McpHostConnector {
  @override
  Future<McpConnection> connect(HostModel host) async =>
      McpConnection(target: _Manager(), jumpManagers: const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Calls that act on a session the agent already holds leave an audit row
/// too, not only the ones that ask the user something.
void main() {
  late AppDatabase db;
  late McpAuditRepository audit;
  late McpSessionPool pool;
  late McpSession session;

  const ctx = McpToolContext(
    clientId: 'client-1',
    clientName: 'Agent',
    workspaceId: 'default',
    connectionScopeId: 'scope-1',
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    audit = McpAuditRepository(db.mcpDao);
    pool = McpSessionPool(connector: _Connector());
    session = await pool.open(
      clientId: ctx.clientId,
      connectionScopeId: ctx.connectionScopeId,
      clientName: ctx.clientName,
      mode: 'guarded',
      host: HostModel(
        id: 'host-a',
        workspaceId: 'default',
        label: 'box',
        hostname: 'box.example.com',
        createdAt: DateTime(2026),
      ),
    );
  });

  tearDown(() async {
    pool.dispose();
    await db.close();
  });

  Future<List<(String, String?, String)>> rows() async => [
    for (final r in await audit.query()) (r.tool, r.hostId, r.decision),
  ];

  test('close_session is audited', () async {
    await CloseSessionTool(
      sessionPool: pool,
      auditRepository: audit,
    ).execute(ctx, {'sessionId': session.sessionId});

    expect(await rows(), [('close_session', 'host-a', 'allowed')]);
  });

  test('interrupt is audited', () async {
    await InterruptTool(
      sessionPool: pool,
      auditRepository: audit,
    ).execute(ctx, {'sessionId': session.sessionId});

    expect(await rows(), [('interrupt', 'host-a', 'allowed')]);
  });

  test('run_command without a live grant is audited as auto-denied', () async {
    final tool = RunCommandTool(
      sessionPool: pool,
      hostsDao: db.hostsDao,
      grantRepository: McpGrantRepository(db.mcpDao),
      approvalRepository: McpApprovalRepository(db.mcpDao),
      auditRepository: audit,
      policyEngine: PolicyEngine(
        approvals: McpApprovalRepository(db.mcpDao),
        dao: db.mcpDao,
      ),
      approvalCoordinator: ApprovalCoordinator(),
      redactor: const OutputRedactor(),
    );

    await expectLater(
      tool.execute(ctx, {'sessionId': session.sessionId, 'command': 'ls'}),
      throwsA(
        isA<McpToolException>().having(
          (e) => e.code,
          'code',
          McpErrorCode.hostAccessRequired,
        ),
      ),
    );

    expect(await rows(), [('run_command', 'host-a', 'auto_denied')]);
  });
}
