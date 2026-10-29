import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// An AI tool whose own config file ShellVibe can add its MCP server to, so
/// connecting it is one click instead of pasting a config by hand.
enum McpAgentApp {
  claudeCode('Claude Code'),
  claudeDesktop('Claude Desktop'),
  cursor('Cursor'),
  antigravity('Antigravity'),
  codex('Codex');

  const McpAgentApp(this.label);

  final String label;
}

/// Where ShellVibe stands in one tool's config file.
enum McpAgentConfigStatus {
  /// Points at this install's bridge.
  installed,

  /// Points at a bridge that is not this install's, e.g. after the app moved.
  outdated,

  /// No ShellVibe entry, or no config file yet.
  missing,

  /// Not something this code edits safely (a comment in the JSON, the entry
  /// spelled another way in TOML), so it is left alone.
  unreadable,
}

const _serverName = 'shellvibe';
const _codexHeader = '[mcp_servers.$_serverName]';

/// The user-level config file [app] reads its MCP servers from, or null when
/// [app] has none on this platform.
String? mcpAgentConfigPath(
  McpAgentApp app, {
  required Map<String, String> environment,
  required bool isWindows,
  required bool isMacOS,
}) {
  final path = isWindows ? p.windows : p.posix;
  final home = environment[isWindows ? 'USERPROFILE' : 'HOME'];
  if (home == null || home.isEmpty) return null;
  final appData = environment['APPDATA'] ?? '';
  return switch (app) {
    McpAgentApp.claudeCode => path.join(home, '.claude.json'),
    McpAgentApp.claudeDesktop when isMacOS => path.join(
      home,
      'Library',
      'Application Support',
      'Claude',
      'claude_desktop_config.json',
    ),
    McpAgentApp.claudeDesktop when isWindows && appData.isNotEmpty => path.join(
      appData,
      'Claude',
      'claude_desktop_config.json',
    ),
    // Claude Desktop has no Linux build.
    McpAgentApp.claudeDesktop => null,
    McpAgentApp.cursor => path.join(home, '.cursor', 'mcp.json'),
    // Shared by the Antigravity CLI (agy) and IDE.
    McpAgentApp.antigravity => path.join(
      home,
      '.gemini',
      'config',
      'mcp_config.json',
    ),
    McpAgentApp.codex => path.join(home, '.codex', 'config.toml'),
  };
}

/// What [text], the config file's content (null when there is no file), says
/// about ShellVibe's entry.
McpAgentConfigStatus mcpAgentConfigStatus(
  McpAgentApp app,
  String? text,
  String command,
) {
  try {
    final current = app == McpAgentApp.codex
        ? _codexCommand(text)
        : _jsonCommand(text);
    if (current == null) return McpAgentConfigStatus.missing;
    return current == command
        ? McpAgentConfigStatus.installed
        : McpAgentConfigStatus.outdated;
  } on FormatException {
    return McpAgentConfigStatus.unreadable;
  }
}

/// [text] with ShellVibe's entry pointing at [command] and everything else
/// kept. Throws [FormatException] when [text] is not safe to edit.
String withMcpAgentServer(McpAgentApp app, String? text, String command) =>
    app == McpAgentApp.codex
    ? _withCodexServer(text, command)
    : _withJsonServer(text, command);

/// Reads [path] and reports [mcpAgentConfigStatus]. A file that cannot be
/// read at all counts as unreadable, not missing, so it is never offered for
/// overwriting.
Future<McpAgentConfigStatus> readMcpAgentConfigStatus(
  McpAgentApp app,
  String path,
  String command,
) async {
  try {
    return mcpAgentConfigStatus(app, await _readIfExists(path), command);
  } on Exception {
    return McpAgentConfigStatus.unreadable;
  }
}

/// Points [app]'s config file at [command], creating it if needed.
Future<void> installMcpAgentServer(
  McpAgentApp app,
  String path,
  String command,
) async {
  final file = File(path);
  final updated = withMcpAgentServer(app, await _readIfExists(path), command);
  await file.parent.create(recursive: true);
  // Rewritten in place, not through a temp file and a rename, which would
  // swap ~/.claude.json's 0600 for the default mode.
  await file.writeAsString(updated, flush: true);
}

Future<String?> _readIfExists(String path) async {
  final file = File(path);
  return await file.exists() ? file.readAsString() : null;
}

Map<String, dynamic> _decodeJson(String? text) {
  if (text == null || text.trim().isEmpty) return {};
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('The config is not a JSON object.');
  }
  return decoded;
}

String? _jsonCommand(String? text) {
  final servers = _decodeJson(text)['mcpServers'];
  final entry = servers is Map ? servers[_serverName] : null;
  final command = entry is Map ? entry['command'] : null;
  return command is String ? command : null;
}

String _withJsonServer(String? text, String command) {
  final config = _decodeJson(text);
  final servers = config['mcpServers'] ??= <String, dynamic>{};
  if (servers is! Map) {
    throw const FormatException('"mcpServers" is not an object.');
  }
  final entry = servers[_serverName];
  // Merged, not replaced: a field added by hand (env, alwaysLoad) survives
  // an update of the path.
  servers[_serverName] = {if (entry is Map) ...entry, 'command': command};
  return '${const JsonEncoder.withIndent('  ').convert(config)}\n';
}

/// Finds ShellVibe's table in Codex's config.toml line by line rather than
/// with a TOML parser, so the rest of the file, comments included, is written
/// back exactly as it was.
///
/// Returns the lines, the header's index and its `command` line's index, -1
/// for either one that is absent.
(List<String>, int, int) _findCodexTable(String? text) {
  final lines = (text ?? '').split('\n');
  final header = lines.indexWhere((line) => line.trim() == _codexHeader);
  if (header == -1) {
    // The same table spelled another way (an inline table, dotted keys) is
    // not edited: appending a second definition would leave Codex unable to
    // load its config at all.
    final otherForm = RegExp(
      r'mcp_servers\.shellvibe|^\s*shellvibe\s*=',
      multiLine: true,
    );
    if (otherForm.hasMatch(text ?? '')) {
      throw const FormatException('ShellVibe is defined in another form.');
    }
    return (lines, -1, -1);
  }
  for (var i = header + 1; i < lines.length; i++) {
    if (lines[i].trimLeft().startsWith('[')) break;
    if (RegExp(r'^\s*command\s*=').hasMatch(lines[i])) {
      return (lines, header, i);
    }
  }
  return (lines, header, -1);
}

String? _codexCommand(String? text) {
  final (lines, _, line) = _findCodexTable(text);
  if (line == -1) return null;
  final value = RegExp(
    r'''^\s*command\s*=\s*("(?:[^"\\]|\\.)*"|'[^']*')\s*(?:#.*)?$''',
  ).firstMatch(lines[line].trimRight())?.group(1);
  if (value == null) throw const FormatException('Unrecognized command.');
  // A TOML basic string reads as JSON; a literal one has no escapes at all.
  return value.startsWith('"')
      ? jsonDecode(value) as String
      : value.substring(1, value.length - 1);
}

String _withCodexServer(String? text, String command) {
  final (lines, header, line) = _findCodexTable(text);
  // A JSON string is also a valid TOML basic string, escapes included.
  final entry = 'command = ${jsonEncode(command)}';
  if (line != -1) {
    lines[line] = entry;
  } else if (header != -1) {
    lines.insert(header + 1, entry);
  } else {
    final body = (text ?? '').trimRight();
    return '${body.isEmpty ? '' : '$body\n\n'}$_codexHeader\n$entry\n';
  }
  return lines.join('\n');
}
