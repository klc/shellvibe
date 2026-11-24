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
///
/// The tool may be running and rewriting the same file (Claude Code keeps
/// `~/.claude.json` up to date as it runs), so the new content goes to a
/// sibling that is renamed over the original: a reader never sees a
/// half-written file. The sibling starts as a copy of the original so it
/// keeps its mode (`~/.claude.json` is 0600). If the original changed while
/// the update was being made, it is made again on top of that change rather
/// than overwriting it.
Future<void> installMcpAgentServer(
  McpAgentApp app,
  String path,
  String command,
) => _rewrite(path, (text) => withMcpAgentServer(app, text, command));

/// Writes [edit] of [path]'s content back to [path], atomically and without
/// losing a concurrent change (see [installMcpAgentServer]).
Future<void> _rewrite(String path, String Function(String? text) edit) async {
  var file = File(path);
  // Through a symlink (a dotfiles repo), not over it.
  if (await file.exists()) file = File(await file.resolveSymbolicLinks());
  await file.parent.create(recursive: true);
  final temp = File('${file.path}.shellvibe-tmp');
  try {
    for (var attempt = 0; ; attempt++) {
      final original = await _readIfExists(file.path);
      final updated = edit(original);
      if (original != null) await file.copy(temp.path);
      await temp.writeAsString(updated, flush: true);
      if (await _readIfExists(file.path) != original && attempt < 2) continue;
      await temp.rename(file.path);
      return;
    }
  } finally {
    if (await temp.exists()) await temp.delete();
  }
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

// --- The ssh hook ---------------------------------------------------------
//
// `shellvibe-mcp hook <agent>` in an agent's own hook config sends that
// agent's `ssh`, `scp`, `sftp` and remote `rsync` back to ShellVibe's tools
// (tool/shellvibe_mcp_bridge/bin/remote_shell_hook.dart). A nudge for an
// agent that forgets the tools, not a lock: `bash -c` walks past it.

/// The name the bridge's `hook` subcommand knows [app] by, or null when [app]
/// has no shell-command hook ShellVibe can add. Antigravity has one, but its
/// contract is not documented anywhere ShellVibe could check it against.
String? mcpHookAgentName(McpAgentApp app) => switch (app) {
  McpAgentApp.claudeCode => 'claude-code',
  McpAgentApp.codex => 'codex',
  McpAgentApp.cursor => 'cursor',
  McpAgentApp.claudeDesktop || McpAgentApp.antigravity => null,
};

/// The user-level file [app] reads its hooks from, or null.
// ponytail: macOS and Linux only. On Windows each agent runs hooks through a
// different shell (Git Bash, PowerShell, Codex's commandWindows) and the
// quoting is untested; add a per-agent command form when it can be tried.
String? mcpHookConfigPath(
  McpAgentApp app, {
  required Map<String, String> environment,
  required bool isWindows,
}) {
  final home = environment['HOME'];
  if (isWindows || home == null || home.isEmpty) return null;
  String dir(String variable, String fallback) {
    final value = environment[variable];
    return value == null || value.isEmpty ? p.join(home, fallback) : value;
  }

  return switch (app) {
    McpAgentApp.claudeCode => p.join(
      dir('CLAUDE_CONFIG_DIR', '.claude'),
      'settings.json',
    ),
    McpAgentApp.codex => p.join(dir('CODEX_HOME', '.codex'), 'hooks.json'),
    McpAgentApp.cursor => p.join(home, '.cursor', 'hooks.json'),
    McpAgentApp.claudeDesktop || McpAgentApp.antigravity => null,
  };
}

/// The hook command line for [app]: the bridge at [bridge], bare when that is
/// safe in any shell and quoted for `sh` otherwise.
String mcpHookCommand(McpAgentApp app, String bridge) {
  final path = RegExp(r'^[A-Za-z0-9_./-]+$').hasMatch(bridge)
      ? bridge
      : "'${bridge.replaceAll("'", r"'\''")}'";
  return '$path hook ${mcpHookAgentName(app)}';
}

/// What [text], [app]'s hook config, says about ShellVibe's hook.
McpAgentConfigStatus mcpHookStatus(
  McpAgentApp app,
  String? text,
  String command,
) {
  try {
    final ours = [
      for (final hook in _hookObjects(app, _decodeJson(text)))
        if (_isOurHook(hook)) hook['command'],
    ];
    if (ours.isEmpty) return McpAgentConfigStatus.missing;
    return ours.every((c) => c == command)
        ? McpAgentConfigStatus.installed
        : McpAgentConfigStatus.outdated;
  } on FormatException {
    return McpAgentConfigStatus.unreadable;
  }
}

/// [text] with ShellVibe's hook set to [command], or removed when [command]
/// is null. Every other hook is kept, and only what removing ours left empty
/// is pruned. Throws [FormatException] when [text] is not safe to edit.
String withMcpHook(McpAgentApp app, String? text, String? command) {
  final config = _decodeJson(text);
  _hookObjects(app, config).length; // Validates the shape before editing.
  final event = _hookEvent(app);
  final hooks = (config['hooks'] ??= <String, dynamic>{}) as Map;
  final entries = (hooks[event] ??= <dynamic>[]) as List;

  if (app == McpAgentApp.cursor) {
    entries.removeWhere(_isOurHook);
  } else {
    final emptied = Set<Object>.identity();
    for (final group in entries) {
      final list = group is Map ? group['hooks'] : null;
      if (list is! List || !list.any(_isOurHook)) continue;
      list.removeWhere(_isOurHook);
      if (list.isEmpty) emptied.add(group as Object);
    }
    entries.removeWhere(emptied.contains);
  }

  if (command != null) {
    if (app == McpAgentApp.cursor) {
      config['version'] ??= 1;
      // Cursor matches this against the whole command, so the bridge is not
      // started for every `ls`.
      entries.add({'command': command, 'matcher': r'\b(ssh|scp|sftp|rsync)\b'});
    } else {
      entries.add({
        'matcher': 'Bash',
        'hooks': [
          {'type': 'command', 'command': command},
        ],
      });
    }
  }
  if (entries.isEmpty) hooks.remove(event);
  if (hooks.isEmpty) config.remove('hooks');
  return '${const JsonEncoder.withIndent('  ').convert(config)}\n';
}

/// Reads [path] and reports [mcpHookStatus]; unreadable when it cannot be
/// read at all.
Future<McpAgentConfigStatus> readMcpHookStatus(
  McpAgentApp app,
  String path,
  String command,
) async {
  try {
    return mcpHookStatus(app, await _readIfExists(path), command);
  } on Exception {
    return McpAgentConfigStatus.unreadable;
  }
}

/// Adds ShellVibe's hook to [app]'s config at [path] pointing at [command],
/// or removes it when [command] is null, the way [installMcpAgentServer]
/// writes.
Future<void> setMcpHook(McpAgentApp app, String path, String? command) async {
  if (command == null && !await File(path).exists()) return;
  await _rewrite(path, (text) => withMcpHook(app, text, command));
}

String _hookEvent(McpAgentApp app) =>
    app == McpAgentApp.cursor ? 'beforeShellExecution' : 'PreToolUse';

bool _isOurHook(Object? hook) {
  final command = hook is Map ? hook['command'] : null;
  return command is String &&
      command.contains('shellvibe-mcp') &&
      command.contains(' hook ');
}

/// Every hook object under [app]'s shell-command event in [config]. Throws
/// [FormatException] when the containers are not the shape the agent reads.
List<Map<dynamic, dynamic>> _hookObjects(
  McpAgentApp app,
  Map<String, dynamic> config,
) {
  final hooks = config['hooks'];
  if (hooks == null) return const [];
  if (hooks is! Map) throw const FormatException('"hooks" is not an object.');
  final entries = hooks[_hookEvent(app)];
  if (entries == null) return const [];
  if (entries is! List) {
    throw FormatException('"${_hookEvent(app)}" is not a list.');
  }
  if (app == McpAgentApp.cursor) return [...entries.whereType<Map>()];
  return [
    for (final group in entries.whereType<Map>())
      if (group['hooks'] is List) ...(group['hooks'] as List).whereType<Map>(),
  ];
}
