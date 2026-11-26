import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/mcp/mcp_errors.dart';
import 'package:shellvibe/core/mcp/mcp_protocol.dart';
import 'package:shellvibe/features/mcp/data/tools/mcp_tool_handler.dart';
import 'package:shellvibe/features/mcp/data/tools/mcp_tool_registry.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';

/// The AI Access switches: a tool group the user turned off is neither
/// listed nor callable, and turning it back on restores it without a restart.
void main() {
  const ctx = McpToolContext(
    clientId: 'c',
    clientName: 'Agent',
    workspaceId: 'w',
    connectionScopeId: 's',
  );

  late McpToolSwitches switches;
  late McpToolRegistry registry;

  setUp(() {
    switches = McpToolSwitches();
    registry = McpToolRegistry([
      _Tool('list_hosts'),
      _Tool('upload_file'),
      _Tool('download_file'),
      _Tool('add_host'),
    ], switches: switches);
  });

  List<String> listed() => [for (final d in registry.definitions()) d.name];

  test('every tool is on by default', () {
    expect(listed(), [
      'list_hosts',
      'upload_file',
      'download_file',
      'add_host',
    ]);
  });

  test('a group that is off is not listed and refuses calls', () async {
    switches.disabled = {McpToolGroup.fileTransfer};

    expect(listed(), ['list_hosts', 'add_host']);
    // Thrown before any work, like an unknown tool; the dispatcher's await
    // inside its try turns it into a tool error for the agent.
    expect(
      () => registry.call(ctx, 'upload_file', const {}),
      throwsA(
        isA<McpToolException>()
            .having((e) => e.code, 'code', McpErrorCode.toolDisabled)
            .having((e) => e.message, 'message', contains('File transfer')),
      ),
    );
    // Tools outside every group stay on.
    expect(await registry.call(ctx, 'list_hosts', const {}), 'list_hosts');
  });

  test('turning a group back on applies to the next call', () async {
    switches.disabled = {McpToolGroup.addHost};
    switches.disabled = const {};

    expect(listed(), contains('add_host'));
    expect(await registry.call(ctx, 'add_host', const {}), 'add_host');
  });

  test('every grouped tool exists in the real tool set', () {
    // A renamed tool would silently fall out of its group and stay on.
    const known = {
      'run_command',
      'interrupt',
      'upload_file',
      'download_file',
      'list_runbooks',
      'run_runbook',
      'get_runbook_run',
      'cancel_runbook_run',
      'list_snippets',
      'run_snippet',
      'add_host',
    };
    expect({for (final g in McpToolGroup.values) ...g.tools}, known);
  });
}

class _Tool implements McpToolHandler {
  _Tool(this.name);

  @override
  final String name;

  @override
  McpToolDefinition get definition => McpToolDefinition(
    name: name,
    description: name,
    inputSchema: const {'type': 'object'},
  );

  @override
  Future<Object?> execute(
    McpToolContext ctx,
    Map<String, Object?> args,
  ) async => name;
}
