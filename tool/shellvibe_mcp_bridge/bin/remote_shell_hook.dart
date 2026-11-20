// `shellvibe-mcp hook <agent>`: an agent's pre-shell-command hook that turns
// `ssh`, `scp`, `sftp` and remote `rsync` away towards ShellVibe's MCP tools.
//
// A steering aid, not a security boundary: `bash -c "ssh h"`, a script or a
// subprocess walk straight past it. It errs towards letting a command run, so
// "ssh" in a quoted string, a commit message or a heredoc is never blocked.
//
// Dependency-free like the rest of the bridge; imported by relative path.

import 'dart:convert';

/// The agents whose hook contract this speaks. Codex took Claude Code's.
const hookAgents = {'claude-code', 'codex', 'cursor'};

/// Reads [input], the agent's hook JSON, and returns what to print on stdout,
/// or null to print nothing and let the command run.
///
/// [appRunning] is only asked when a command is blocked.
Future<String?> hookOutput(
  String agent,
  String input, {
  required Future<bool> Function() appRunning,
}) async {
  final cursor = agent == 'cursor';
  final allow = cursor ? jsonEncode({'permission': 'allow'}) : null;

  String? command;
  try {
    final json = jsonDecode(input);
    if (json is Map) {
      final toolInput = json['tool_input'];
      final value = cursor
          ? json['command']
          : (toolInput is Map ? toolInput['command'] : null);
      if (value is String) command = value;
    }
  } on FormatException {
    // Unreadable input: let the command run rather than block everything.
  }
  final tool = command == null ? null : blockedRemoteTool(command);
  if (tool == null) return allow;

  final message = denyMessage(tool, appRunning: await appRunning());
  return jsonEncode(
    cursor
        ? {
            'permission': 'deny',
            'user_message': 'ShellVibe sent `$tool` to its MCP tools.',
            'agent_message': message,
          }
        : {
            'hookSpecificOutput': {
              'hookEventName': 'PreToolUse',
              'permissionDecision': 'deny',
              'permissionDecisionReason': message,
            },
          },
  );
}

String denyMessage(String tool, {required bool appRunning}) =>
    '${appRunning ? '' : 'ShellVibe is not running, or its AI access is off: '
              'ask the user to open it and turn AI access on. '}'
    'Do not run `$tool` here. Reach the user\'s servers through the '
    'ShellVibe MCP tools: list_hosts -> request_host_access -> open_session '
    '-> run_command, and upload_file / download_file to copy a file. If the '
    'server is not in ShellVibe, offer add_host or ask the user to add it. '
    'Do not work '
    'around this block (bash -c, a script, another binary): the user can '
    'turn it off in ShellVibe under Settings > AI access.';

/// The remote shell tool [command] runs, or null.
///
/// Matches the command word of each simple command (after `;`, `&&`, `|`,
/// `(`, `$(` or a newline), past env assignments and wrappers like `sudo` or
/// `env`. `rsync` counts only with a remote operand.
// ponytail: wrapper options that take a value (`sudo -u root ssh`) hide the
// command; add per-wrapper option tables if agents are seen doing that.
String? blockedRemoteTool(String command) {
  for (final words in _simpleCommands(command)) {
    var i = 0;
    while (i < words.length &&
        (_wrappers.contains(words[i]) ||
            words[i].startsWith('-') ||
            _assignment.hasMatch(words[i]) ||
            _number.hasMatch(words[i]))) {
      // `command -v ssh` asks whether ssh exists; it does not run it.
      if (words[i] == 'command' &&
          i + 1 < words.length &&
          (words[i + 1] == '-v' || words[i + 1] == '-V')) {
        i = words.length;
        break;
      }
      i++;
    }
    if (i == words.length) continue;
    final name = words[i].split('/').last;
    final args = words.sublist(i + 1);
    if (name == 'ssh' || name == 'scp' || name == 'sftp') return name;
    if (name == 'rsync' && args.any(_remoteRsyncArg)) return name;
  }
  return null;
}

const _wrappers = {
  'sudo',
  'doas',
  'env',
  'exec',
  'command',
  'builtin',
  'nohup',
  'time',
  'nice',
  'timeout',
};

final _assignment = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=');
final _remoteOperand = RegExp(r'^[^/:]+:');
// A wrapper's numeric argument: `timeout 5`, `nice -n 10`.
final _number = RegExp(r'^\d+(\.\d+)?[smhd]?$');

bool _remoteRsyncArg(String arg) =>
    arg == '-e' ||
    arg.startsWith('--rsh') ||
    arg.startsWith('rsync://') ||
    (!arg.startsWith('-') && _remoteOperand.hasMatch(arg));

/// [command] split into simple commands, each a list of words with quotes
/// and escapes removed. Quoted text never splits or starts a command. Reading
/// stops at a heredoc (`<<`), whose body is text, and a comment skips to the
/// end of its line.
List<List<String>> _simpleCommands(String command) {
  final commands = <List<String>>[[]];
  final word = StringBuffer();
  var inWord = false;
  String? quote;

  void endWord() {
    if (!inWord) return;
    commands.last.add(word.toString());
    word.clear();
    inWord = false;
  }

  void endCommand() {
    endWord();
    if (commands.last.isNotEmpty) commands.add([]);
  }

  for (var i = 0; i < command.length; i++) {
    final c = command[i];
    if (quote != null) {
      // A heredoc inside `"$(cat <<EOF ...)"` is text too, quotes and all.
      if (quote == '"' && command.startsWith('<<', i)) break;
      if (c == quote) {
        quote = null;
      } else if (c == r'\' && quote == '"' && i + 1 < command.length) {
        word.write(command[++i]);
      } else {
        word.write(c);
      }
      continue;
    }
    if (c == r'\' && i + 1 < command.length) {
      // A backslash-newline continues the line.
      if (command[++i] == '\n') {
        endWord();
      } else {
        word.write(command[i]);
        inWord = true;
      }
    } else if (c == '"' || c == "'") {
      quote = c;
      inWord = true;
    } else if (command.startsWith('<<', i)) {
      break;
    } else if (c == '#' && !inWord) {
      final end = command.indexOf('\n', i);
      if (end == -1) break;
      i = end - 1;
    } else if (c == r'$' && command.startsWith(r'$(', i)) {
      endCommand();
      i++;
    } else if (';&|()`\n'.contains(c)) {
      endCommand();
    } else if (c == ' ' || c == '\t') {
      endWord();
    } else {
      word.write(c);
      inWord = true;
    }
  }
  endWord();
  return [
    for (final c in commands)
      if (c.isNotEmpty) c,
  ];
}
