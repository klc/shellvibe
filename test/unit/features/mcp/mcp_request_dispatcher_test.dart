import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/mcp/mcp_protocol.dart';
import 'package:shellvibe/features/mcp/data/mcp_request_dispatcher.dart';
import 'package:shellvibe/features/mcp/data/tools/mcp_tool_handler.dart';
import 'package:shellvibe/features/mcp/data/tools/mcp_tool_registry.dart';

/// Records the context every call arrives with.
final class _RecordingTool implements McpToolHandler {
  final List<McpToolContext> calls = [];
  Map<String, Object?>? lastArgs;

  @override
  String get name => 'record';

  @override
  McpToolDefinition get definition => const McpToolDefinition(
    name: 'record',
    description: 'Records the context it is called with.',
    inputSchema: {'type': 'object'},
  );

  @override
  Future<Object?> execute(McpToolContext ctx, Map<String, Object?> args) async {
    calls.add(ctx);
    lastArgs = args;

    return const {'ok': true};
  }
}

/// What "this session" means on a server that speaks HTTP: the stretch
/// between one client's `initialize` and its next.
void main() {
  late _RecordingTool tool;
  late List<String> ended;
  late McpRequestDispatcher dispatcher;
  var ids = 0;

  setUp(() {
    tool = _RecordingTool();
    ended = [];
    dispatcher = McpRequestDispatcher(
      registry: McpToolRegistry([tool]),
      lookupClient: (clientId) async =>
          (name: 'Agent $clientId', workspaceId: 'default'),
      onScopeEnded: ended.add,
    );
  });

  Future<void> initialize(String clientId) => dispatcher.handle(
    clientId,
    JsonRpcRequest(id: ++ids, method: McpMethod.initialize),
  );

  Future<String> scopeOfACall(String clientId) async {
    await dispatcher.handle(
      clientId,
      JsonRpcRequest(
        id: ++ids,
        method: McpMethod.toolsCall,
        params: const {'name': 'record'},
      ),
    );

    return tool.calls.last.connectionScopeId;
  }

  test('snake_case argument names reach the tool as camelCase', () async {
    await dispatcher.handle(
      'client-1',
      JsonRpcRequest(
        id: ++ids,
        method: McpMethod.toolsCall,
        params: const {
          'name': 'record',
          'arguments': {'session_id': 's-1', 'command': 'ls'},
        },
      ),
    );

    expect(tool.lastArgs, {'sessionId': 's-1', 'command': 'ls'});
  });

  test(
    'initialize tells the agent to use these tools instead of ssh',
    () async {
      final result =
          await dispatcher.handle(
                'client-1',
                JsonRpcRequest(id: ++ids, method: McpMethod.initialize),
              )
              as Map<String, Object?>;

      expect(result['instructions'], contains('ssh'));
      expect((result['instructions'] as String).length, lessThan(2048));
    },
  );

  test('calls between two handshakes share one scope', () async {
    await initialize('client-1');

    expect(await scopeOfACall('client-1'), await scopeOfACall('client-1'));
    expect(ended, isEmpty);
  });

  test('a new handshake starts a new scope and ends the old one', () async {
    await initialize('client-1');
    final first = await scopeOfACall('client-1');

    await initialize('client-1');
    final second = await scopeOfACall('client-1');

    expect(second, isNot(first));
    expect(ended, [first]);
  });

  test('one client reconnecting does not end another\'s session', () async {
    await initialize('client-1');
    await initialize('client-2');
    final other = await scopeOfACall('client-2');

    await initialize('client-1');

    expect(await scopeOfACall('client-2'), other);
    expect(ended, isNot(contains(other)));
  });
}
