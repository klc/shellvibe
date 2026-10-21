import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/ssh_session_manager.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/mcp/data/mcp_host_connector.dart';
import 'package:shellvibe/features/snippets/data/services/ssh_remote_command_session_factory.dart';
import 'package:shellvibe/features/snippets/domain/services/remote_command_session.dart';

import '../../core/mcp/fake_shell_channel.dart';

/// An [SSHSession] whose bytes come from a [FakeShellChannel].
class _ChannelSession implements SSHSession {
  _ChannelSession(this.fake);

  final FakeShellChannel fake;

  @override
  Stream<Uint8List> get stdout =>
      fake.stdout.map((b) => Uint8List.fromList(b));

  @override
  Stream<Uint8List> get stderr =>
      fake.stderr.map((b) => Uint8List.fromList(b));

  @override
  Future<void> get done => Completer<void>().future;

  @override
  void write(Uint8List data) => fake.write(data);

  @override
  void kill(SSHSignal signal) => fake.sendInterrupt();

  @override
  void close() => fake.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ShellManager implements SSHSessionManager {
  _ShellManager(this.first);

  final FakeShellChannel first;
  int opened = 0;

  @override
  Future<SSHSession> openShell({
    String terminalType = 'xterm-256color',
    int width = 80,
    int height = 24,
    int pixelWidth = 0,
    int pixelHeight = 0,
    Map<String, String>? environment,
    bool requestPty = true,
  }) async =>
      _ChannelSession(opened++ == 0 ? first : FakeShellChannel());

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ShellConnector implements McpHostConnector {
  _ShellConnector(this.manager);

  final _ShellManager manager;

  @override
  Future<McpConnection> connect(HostModel host) async =>
      McpConnection(target: manager, jumpManagers: const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingConnector implements McpHostConnector {
  int connects = 0;

  @override
  Future<McpConnection> connect(HostModel host) async {
    connects++;
    throw StateError('should not be reached');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('rejects local hosts before touching the network', () async {
    final connector = _ThrowingConnector();
    final factory = SshRemoteCommandSessionFactory(connector: connector);
    final local = HostModel(
      id: 'l',
      workspaceId: 'w',
      label: 'This Mac',
      hostname: 'localhost',
      protocol: 'local',
      createdAt: DateTime(2026),
    );

    await expectLater(
      factory.open(local),
      throwsA(
        isA<RemoteCommandException>().having(
          (e) => e.message,
          'message',
          contains('local shell'),
        ),
      ),
    );
    expect(connector.connects, 0);
  });

  test('a shell reset after a hung step is reported as a timeout', () async {
    final channel = FakeShellChannel();
    final factory = SshRemoteCommandSessionFactory(
      connector: _ShellConnector(_ShellManager(channel)),
    );
    final session = await factory.open(
      HostModel(
        id: 'h',
        workspaceId: 'w',
        label: 'box',
        hostname: 'box.example.com',
        createdAt: DateTime(2026),
      ),
    );

    // Nothing answers, not even the interrupt or the probe: the session
    // rebuilds the shell and reports a reset with exit code -1.
    channel.autoRespond = false;

    await expectLater(
      session.run('sleep 999', const Duration(milliseconds: 50)),
      throwsA(
        isA<TimeoutException>().having(
          (e) => e.message,
          'message',
          contains('reset'),
        ),
      ),
    );
    await session.close();
  }, timeout: const Timeout(Duration(seconds: 30)));
}
