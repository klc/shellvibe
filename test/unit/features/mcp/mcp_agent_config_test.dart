import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/mcp/data/mcp_agent_config.dart';

const _bridge = '/Applications/ShellVibe.app/Contents/MacOS/shellvibe-mcp';

void main() {
  group('JSON configs', () {
    const app = McpAgentApp.claudeCode;

    test('a missing file gets just the ShellVibe entry', () {
      expect(
        mcpAgentConfigStatus(app, null, _bridge),
        McpAgentConfigStatus.missing,
      );

      final written = withMcpAgentServer(app, null, _bridge);

      expect(jsonDecode(written), {
        'mcpServers': {
          'shellvibe': {'command': _bridge},
        },
      });
      expect(
        mcpAgentConfigStatus(app, written, _bridge),
        McpAgentConfigStatus.installed,
      );
    });

    test('an update keeps every other key, server and entry field', () {
      final existing = jsonEncode({
        'numStartups': 12,
        'mcpServers': {
          'codegraph': {'command': 'codegraph'},
          'shellvibe': {'command': '/old/shellvibe-mcp', 'alwaysLoad': true},
        },
      });
      expect(
        mcpAgentConfigStatus(app, existing, _bridge),
        McpAgentConfigStatus.outdated,
      );

      expect(jsonDecode(withMcpAgentServer(app, existing, _bridge)), {
        'numStartups': 12,
        'mcpServers': {
          'codegraph': {'command': 'codegraph'},
          'shellvibe': {'command': _bridge, 'alwaysLoad': true},
        },
      });
    });

    test('a file with comments is reported and never rewritten', () {
      const commented = '{\n  // mine\n  "mcpServers": {}\n}';

      expect(
        mcpAgentConfigStatus(app, commented, _bridge),
        McpAgentConfigStatus.unreadable,
      );
      expect(
        () => withMcpAgentServer(app, commented, _bridge),
        throwsFormatException,
      );
    });
  });

  group('Codex config.toml', () {
    const app = McpAgentApp.codex;

    test('the table is appended and the rest kept byte for byte', () {
      const existing =
          '# my settings\nmodel = "gpt-5"\n\n[projects."/x/shellvibe"]\ntrust_level = "trusted"\n';

      final written = withMcpAgentServer(app, existing, _bridge);

      expect(
        written,
        '${existing.trimRight()}\n\n[mcp_servers.shellvibe]\ncommand = "$_bridge"\n',
      );
      expect(
        mcpAgentConfigStatus(app, written, _bridge),
        McpAgentConfigStatus.installed,
      );
    });

    test('an existing command is replaced in place', () {
      const existing =
          "[mcp_servers.shellvibe]\ncommand = 'C:\\old\\shellvibe-mcp.exe'\nargs = []\n\n[other]\ncommand = \"keep\"\n";
      expect(
        mcpAgentConfigStatus(app, existing, _bridge),
        McpAgentConfigStatus.outdated,
      );

      expect(
        withMcpAgentServer(app, existing, _bridge),
        '[mcp_servers.shellvibe]\ncommand = "$_bridge"\nargs = []\n\n[other]\ncommand = "keep"\n',
      );
    });

    test('the table spelled another way is left alone', () {
      const inline = '[mcp_servers]\nshellvibe = { command = "/old" }\n';

      expect(
        mcpAgentConfigStatus(app, inline, _bridge),
        McpAgentConfigStatus.unreadable,
      );
      expect(
        () => withMcpAgentServer(app, inline, _bridge),
        throwsFormatException,
      );
    });
  });

  test('Claude Desktop has no config path on Linux', () {
    expect(
      mcpAgentConfigPath(
        McpAgentApp.claudeDesktop,
        environment: {'HOME': '/home/me'},
        isWindows: false,
        isMacOS: false,
      ),
      isNull,
    );
    expect(
      mcpAgentConfigPath(
        McpAgentApp.claudeDesktop,
        environment: {
          'USERPROFILE': r'C:\Users\me',
          'APPDATA': r'C:\Users\me\AppData\Roaming',
        },
        isWindows: true,
        isMacOS: false,
      ),
      r'C:\Users\me\AppData\Roaming\Claude\claude_desktop_config.json',
    );
  });

  test('installing keeps the file private', () async {
    final dir = await Directory.systemTemp.createTemp('mcp_agent_config');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/.claude.json')..writeAsStringSync('{}');
    await Process.run('chmod', ['600', file.path]);

    await installMcpAgentServer(McpAgentApp.claudeCode, file.path, _bridge);

    expect(file.statSync().modeString(), 'rw-------');
    expect(
      mcpAgentConfigStatus(
        McpAgentApp.claudeCode,
        file.readAsStringSync(),
        _bridge,
      ),
      McpAgentConfigStatus.installed,
    );
  }, skip: Platform.isWindows);
}
