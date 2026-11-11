import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/ssh_session_manager.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/mcp/data/mcp_host_connector.dart';
import 'package:shellvibe/features/mcp/data/mcp_session_pool.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_models.dart';

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

/// Every agent window shares one client token; a session belongs to the
/// connection that opened it.
void main() {
  late McpSessionPool pool;

  setUp(() => pool = McpSessionPool(connector: _Connector()));
  tearDown(() => pool.dispose());

  test(
    'another connection of the same client cannot see or use a session',
    () async {
      final session = await pool.open(
        clientId: 'client-1',
        connectionScopeId: 'window-a',
        clientName: 'claude-code',
        mode: 'guarded',
        host: HostModel(
          id: 'h',
          workspaceId: 'w',
          label: 'box',
          hostname: 'box.example.com',
          createdAt: DateTime(2026),
        ),
      );

      expect(
        pool.requireOwned('client-1', 'window-a', session.sessionId),
        same(session),
      );
      expect(
        () => pool.requireOwned('client-1', 'window-b', session.sessionId),
        throwsA(
          isA<McpToolException>().having(
            (e) => e.code,
            'code',
            McpErrorCode.sessionNotFound,
          ),
        ),
      );
      expect(
        pool.sessionsForClient('client-1', connectionScopeId: 'window-b'),
        isEmpty,
      );
      expect(pool.sessionsForClient('client-1'), [session]);
    },
  );
}
