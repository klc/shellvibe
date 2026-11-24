import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/shellvibe_mcp_bridge/bin/remote_shell_hook.dart';

void main() {
  group('blockedRemoteTool', () {
    const mustBlock = {
      'ssh web1': 'ssh',
      'ssh -i ~/.ssh/id user@host uptime': 'ssh',
      '/usr/bin/ssh host': 'ssh',
      'cd x && ssh host ls': 'ssh',
      'ls; ssh host': 'ssh',
      'echo hi | ssh host cat': 'ssh',
      'true || scp a host:b': 'scp',
      'sudo ssh host': 'ssh',
      'env TERM=xterm ssh host': 'ssh',
      'FOO=1 ssh host': 'ssh',
      'echo \$(ssh host hostname)': 'ssh',
      '(cd /tmp; sftp host)': 'sftp',
      'nohup ssh -N -L 8080:localhost:80 host &': 'ssh',
      'ls\nssh host': 'ssh',
      'scp file.txt user@host:/tmp/': 'scp',
      'rsync -avz dist/ user@host:/var/www/': 'rsync',
      'rsync -a -e ssh dist/ host2/': 'rsync',
      'rsync rsync://mirror/pub/ local/': 'rsync',
      '# note\nssh host': 'ssh',
      'cd x && \\\nssh host': 'ssh',
      'timeout 5 ssh host': 'ssh',
      'nice -n 10 scp a h:b': 'scp',
    };
    const mustPass = [
      'ls -la',
      'ssh-keygen -t ed25519',
      'ssh-add ~/.ssh/id_ed25519',
      'git push origin main',
      'cat ~/.ssh/config',
      'which ssh',
      'man scp',
      'grep -E "ssh|scp" lib',
      "grep -rn 'ssh host' .",
      'git commit -m "fix; ssh retry"',
      'echo "run ssh web1 later"',
      'rsync -a build/ dist/',
      'rsync -av --delete ./a/ /tmp/b/',
      'cat <<EOF\nssh host\nEOF',
      'git commit -F - <<\'EOF\'\nfeat: ssh hook\n\nssh host; scp a b\nEOF',
      'flutter test test/unit/ssh_test.dart',
      '# ssh host',
      'echo ssh',
      'command -v ssh',
      'command -V scp >/dev/null && echo ok',
      'gh pr create --body "\$(cat <<\'EOF\'\nSay "hi"; ssh host\nssh web1\nEOF\n)"',
      '',
    ];

    for (final MapEntry(key: command, value: tool) in mustBlock.entries) {
      test('blocks ${jsonEncode(command)}', () {
        expect(blockedRemoteTool(command), tool);
      });
    }
    for (final command in mustPass) {
      test('lets ${jsonEncode(command)} run', () {
        expect(blockedRemoteTool(command), isNull);
      });
    }
  });

  group('hookOutput', () {
    Future<bool> running() async => true;
    Future<bool> closed() async => false;

    test('Claude Code and Codex: silence for a command that may run', () async {
      for (final agent in ['claude-code', 'codex']) {
        await expectLater(
          hookOutput(
            agent,
            jsonEncode({
              'tool_name': 'Bash',
              'tool_input': {'command': 'ls'},
            }),
            appRunning: running,
          ),
          completion(isNull),
        );
      }
    });

    test('Claude Code: the deny names the tools', () async {
      final out = await hookOutput(
        'claude-code',
        jsonEncode({
          'tool_name': 'Bash',
          'tool_input': {'command': 'ssh web1 uptime'},
        }),
        appRunning: running,
      );
      final specific = (jsonDecode(out!) as Map)['hookSpecificOutput'] as Map;
      expect(specific['hookEventName'], 'PreToolUse');
      expect(specific['permissionDecision'], 'deny');
      expect(specific['permissionDecisionReason'], contains('run_command'));
      expect(specific['permissionDecisionReason'], contains('upload_file'));
      expect(
        specific['permissionDecisionReason'],
        isNot(contains('not running')),
      );
    });

    test('says when the app is closed', () async {
      final out = await hookOutput(
        'codex',
        jsonEncode({
          'tool_input': {'command': 'scp a h:b'},
        }),
        appRunning: closed,
      );
      expect(out, contains('not running'));
    });

    test('Cursor: always answers, allow or deny', () async {
      expect(
        jsonDecode(
          (await hookOutput(
            'cursor',
            jsonEncode({'command': 'ls'}),
            appRunning: running,
          ))!,
        ),
        {'permission': 'allow'},
      );
      final deny =
          jsonDecode(
                (await hookOutput(
                  'cursor',
                  jsonEncode({'command': 'ssh h'}),
                  appRunning: running,
                ))!,
              )
              as Map;
      expect(deny['permission'], 'deny');
      expect(deny['agent_message'], contains('list_hosts'));
      expect(deny['user_message'], isNotEmpty);
    });

    test('unreadable input lets the command run', () async {
      expect(
        await hookOutput('claude-code', 'not json', appRunning: running),
        isNull,
      );
      expect(
        await hookOutput('cursor', '[1]', appRunning: running),
        jsonEncode({'permission': 'allow'}),
      );
    });

    test('the app is only checked for a blocked command', () async {
      var asked = 0;
      await hookOutput(
        'claude-code',
        jsonEncode({
          'tool_input': {'command': 'ls'},
        }),
        appRunning: () async {
          asked++;
          return true;
        },
      );
      expect(asked, 0);
    });
  });
}
