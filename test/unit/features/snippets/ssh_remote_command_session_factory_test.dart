import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/mcp/data/mcp_host_connector.dart';
import 'package:shellvibe/features/snippets/data/services/ssh_remote_command_session_factory.dart';
import 'package:shellvibe/features/snippets/domain/services/remote_command_session.dart';

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
}
