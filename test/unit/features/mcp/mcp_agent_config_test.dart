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

  test(
    'installing writes through a symlink and leaves no temp file behind',
    () async {
      final dir = await Directory.systemTemp.createTemp('mcp_agent_config');
      addTearDown(() => dir.delete(recursive: true));
      final real = File('${dir.path}/dotfiles/claude.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"theme": "dark"}');
      final link = Link('${dir.path}/.claude.json')..createSync(real.path);

      await installMcpAgentServer(McpAgentApp.claudeCode, link.path, _bridge);

      expect(FileSystemEntity.isLinkSync(link.path), isTrue);
      final written = jsonDecode(real.readAsStringSync()) as Map;
      expect(written['theme'], 'dark');
      expect(
        mcpAgentConfigStatus(
          McpAgentApp.claudeCode,
          real.readAsStringSync(),
          _bridge,
        ),
        McpAgentConfigStatus.installed,
      );
      expect(
        dir.listSync(recursive: true).map((e) => e.path),
        everyElement(isNot(contains('shellvibe-tmp'))),
      );
    },
    skip: Platform.isWindows,
  );

  group('ssh hook', () {
    final claude = mcpHookCommand(McpAgentApp.claudeCode, _bridge);
    final cursor = mcpHookCommand(McpAgentApp.cursor, _bridge);

    test('the command quotes the bridge only when it must', () {
      expect(claude, '$_bridge hook claude-code');
      expect(
        mcpHookCommand(McpAgentApp.codex, "/opt/it's/shellvibe-mcp"),
        r"'/opt/it'\''s/shellvibe-mcp' hook codex",
      );
    });

    test('paths follow CLAUDE_CONFIG_DIR and CODEX_HOME, not Windows', () {
      String? path(McpAgentApp app, Map<String, String> env) =>
          mcpHookConfigPath(app, environment: env, isWindows: false);
      const home = {'HOME': '/home/me'};
      expect(
        path(McpAgentApp.claudeCode, home),
        '/home/me/.claude/settings.json',
      );
      expect(
        path(McpAgentApp.claudeCode, {...home, 'CLAUDE_CONFIG_DIR': '/c'}),
        '/c/settings.json',
      );
      expect(path(McpAgentApp.codex, home), '/home/me/.codex/hooks.json');
      expect(
        path(McpAgentApp.codex, {...home, 'CODEX_HOME': '/x'}),
        '/x/hooks.json',
      );
      expect(path(McpAgentApp.cursor, home), '/home/me/.cursor/hooks.json');
      expect(path(McpAgentApp.antigravity, home), isNull);
      expect(path(McpAgentApp.claudeDesktop, home), isNull);
      expect(
        mcpHookConfigPath(
          McpAgentApp.claudeCode,
          environment: home,
          isWindows: true,
        ),
        isNull,
      );
    });

    test('Claude Code: added beside other hooks, then removed leaving them '
        'and the rest of the settings exactly', () {
      const app = McpAgentApp.claudeCode;
      final original = {
        'model': 'opus',
        'hooks': {
          'PreToolUse': [
            {
              'matcher': 'Bash',
              'hooks': [
                {'type': 'command', 'command': 'my-guard'},
              ],
            },
          ],
          'Stop': [
            {
              'hooks': [
                {'type': 'command', 'command': 'notify'},
              ],
            },
          ],
        },
      };
      final text = jsonEncode(original);
      expect(mcpHookStatus(app, text, claude), McpAgentConfigStatus.missing);

      final added = withMcpHook(app, text, claude);
      expect(mcpHookStatus(app, added, claude), McpAgentConfigStatus.installed);
      final pre = (jsonDecode(added) as Map)['hooks']['PreToolUse'] as List;
      expect(pre, hasLength(2));
      expect(pre.last, {
        'matcher': 'Bash',
        'hooks': [
          {'type': 'command', 'command': claude},
        ],
      });

      // Adding again replaces rather than duplicates.
      expect(withMcpHook(app, added, claude), added);

      expect(jsonDecode(withMcpHook(app, added, null)), original);
    });

    test('a hook pointing at a moved bridge is outdated and updated in '
        'place', () {
      const app = McpAgentApp.codex;
      final old = withMcpHook(
        app,
        null,
        mcpHookCommand(app, '/old/shellvibe-mcp'),
      );
      final command = mcpHookCommand(app, _bridge);
      expect(mcpHookStatus(app, old, command), McpAgentConfigStatus.outdated);
      final updated = withMcpHook(app, old, command);
      expect(
        mcpHookStatus(app, updated, command),
        McpAgentConfigStatus.installed,
      );
      expect(updated, isNot(contains('/old/')));
    });

    test('removing the only hook leaves an empty config, not empty '
        'containers', () {
      const app = McpAgentApp.claudeCode;
      final added = withMcpHook(app, '{"model":"opus"}', claude);
      expect(jsonDecode(withMcpHook(app, added, null)), {'model': 'opus'});
    });

    test('Cursor: version, a matcher, and other hooks kept', () {
      const app = McpAgentApp.cursor;
      final text = jsonEncode({
        'version': 1,
        'hooks': {
          'beforeShellExecution': [
            {'command': 'kube-guard'},
          ],
          'afterFileEdit': [
            {'command': 'fmt'},
          ],
        },
      });
      final added = jsonDecode(withMcpHook(app, text, cursor)) as Map;
      final before = added['hooks']['beforeShellExecution'] as List;
      expect(before.first, {'command': 'kube-guard'});
      expect(before.last['command'], cursor);
      expect(before.last['matcher'], contains('ssh'));
      expect(
        jsonDecode(withMcpHook(app, jsonEncode(added), null)),
        jsonDecode(text),
      );
      expect((jsonDecode(withMcpHook(app, null, cursor)) as Map)['version'], 1);
    });

    test('a shape the agent would not read is left alone', () {
      const app = McpAgentApp.claudeCode;
      for (final text in [
        '{"hooks": []}',
        '{"hooks": {"PreToolUse": {}}}',
        '// comment\n{}',
      ]) {
        expect(
          mcpHookStatus(app, text, claude),
          McpAgentConfigStatus.unreadable,
        );
        expect(() => withMcpHook(app, text, claude), throwsFormatException);
      }
    });

    test('setMcpHook writes the file, and removing from no file creates '
        'none', () async {
      final dir = await Directory.systemTemp.createTemp('mcp_hook');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/sub/settings.json');

      await setMcpHook(McpAgentApp.claudeCode, file.path, null);
      expect(await file.exists(), isFalse);

      await setMcpHook(McpAgentApp.claudeCode, file.path, claude);
      expect(
        await readMcpHookStatus(McpAgentApp.claudeCode, file.path, claude),
        McpAgentConfigStatus.installed,
      );
      await setMcpHook(McpAgentApp.claudeCode, file.path, null);
      expect(
        await readMcpHookStatus(McpAgentApp.claudeCode, file.path, claude),
        McpAgentConfigStatus.missing,
      );
    });
  });
}
