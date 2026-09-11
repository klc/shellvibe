import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/mcp/shell/persistent_shell_session.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_models.dart';

import 'fake_shell_channel.dart';

/// Builds an initialized session over [channel].
///
/// [reopened] collects every channel handed out by the `reopen` callback, so
/// a test can assert the recovery path actually rebuilt the channel and can
/// drive the replacement.
Future<PersistentShellSession> _session(
  FakeShellChannel channel, {
  List<FakeShellChannel>? reopened,
  int outputCapBytes = 100 * 1024,
}) async {
  final session = PersistentShellSession(
    channel: channel,
    outputCapBytes: outputCapBytes,
    reopen: () async {
      final next = FakeShellChannel(cwd: channel.cwd);
      reopened?.add(next);
      return next;
    },
  );
  await session.initialize();
  return session;
}

void main() {
  group('initialize', () {
    test('normalizes the shell with exec /bin/sh before the exports', () async {
      final channel = FakeShellChannel();
      await _session(channel);

      // `exec /bin/sh` must come first: on fish or csh the export lines are
      // syntax errors, not no-ops.
      expect(channel.writes.first, 'exec /bin/sh\n');
      expect(channel.writes[1], contains('TERM=dumb'));
      expect(channel.writes[1], contains('PAGER=cat'));
      expect(channel.writes[1], contains('unset HISTFILE'));
      // Guarded, not bare: a bare `set +o history` is fatal on dash, whose
      // `set` has no such option — see [PersistentShellSession.initialize].
      expect(
        channel.writes[1],
        contains('(set +o history) 2>/dev/null && set +o history'),
      );
    });

    test('adopts the cwd the probe reports', () async {
      final channel = FakeShellChannel(cwd: '/srv/app');
      final session = await _session(channel);
      expect(session.cwd, '/srv/app');
    });

    test(
      'throws SHELL_UNSUPPORTED when the probe never answers',
      () async {
        final channel = FakeShellChannel(autoRespond: false);
        final session = PersistentShellSession(
          channel: channel,
          reopen: () async => FakeShellChannel(),
        );

        await expectLater(
          session.initialize(),
          throwsA(
            isA<McpToolException>().having(
              (e) => e.code,
              'code',
              McpErrorCode.shellUnsupported,
            ),
          ),
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  group('running a command', () {
    test('returns stdout, exit code and cwd', () async {
      final channel = FakeShellChannel(cwd: '/var/log');
      final session = await _session(channel);

      channel.autoRespond = false;
      final future = session.run('df -h');
      await pumpEventQueue();
      channel.emitStdout('Filesystem  Size\n/dev/sda1   40G\n');
      channel.emitSentinel(channel.pendingNonce);

      final result = await future;
      expect(result.stdout, contains('/dev/sda1'));
      expect(result.exitCode, 0);
      expect(result.cwd, '/var/log');
      expect(result.interrupted, isFalse);
      expect(result.sessionReset, isFalse);
      expect(channel.commandAt(1), 'df -h');
    });

    test('reports a non-zero exit code faithfully', () async {
      final channel = FakeShellChannel();
      final session = await _session(channel);

      channel.nextExitCode = 127;
      final result = await session.run('nosuchbinary');
      expect(result.exitCode, 127);
    });

    test('keeps stderr separate from stdout', () async {
      final channel = FakeShellChannel();
      final session = await _session(channel);

      channel.autoRespond = false;
      final future = session.run('ls /nope');
      await pumpEventQueue();
      channel.emitStdout('on stdout\n');
      channel.emitStderr('ls: /nope: No such file\n');
      channel.emitSentinel(channel.pendingNonce, exitCode: 2);

      final result = await future;
      expect(result.stdout, 'on stdout\n');
      expect(result.stderr, contains('No such file'));
      expect(result.exitCode, 2);
    });

    test('a multi-line command is sent inside one envelope', () async {
      final channel = FakeShellChannel();
      final session = await _session(channel);

      const command = 'for f in a b c\ndo\n  echo \$f\ndone';
      await session.run(command);
      expect(channel.envelopes.length, 2);
      expect(channel.envelopes[1], contains('echo \$f'));
    });

    test(
      'a sentinel split across chunks still completes the command',
      () async {
        final channel = FakeShellChannel();
        final session = await _session(channel);

        channel.autoRespond = false;
        final future = session.run('echo hi');
        await pumpEventQueue();
        channel.emitStdout('hi\n');
        channel.emitSentinelSplit(channel.pendingNonce, cwd: '/split');

        final result = await future;
        expect(result.stdout, 'hi\n');
        expect(result.cwd, '/split');
      },
    );
  });

  group('marker spoofing', () {
    test(
      "output carrying another nonce's marker does not end the command",
      () async {
        final channel = FakeShellChannel();
        final session = await _session(channel);

        channel.autoRespond = false;
        final future = session.run('cat build.log');
        await pumpEventQueue();
        // A decoy that looks exactly like a sentinel but is not ours.
        channel.emitStdout('\n__TERLY_deadbeefdeadbeef__0|/spoofed\n');
        channel.emitStdout('real output\n');
        channel.emitSentinel(channel.pendingNonce, cwd: '/genuine');

        final result = await future;
        expect(result.cwd, '/genuine', reason: 'the decoy must not set cwd');
        expect(result.stdout, contains('__TERLY_deadbeefdeadbeef__'));
        expect(result.stdout, contains('real output'));
      },
    );
  });

  group('cwd tracking', () {
    test('a cwd change reported by the sentinel is carried forward', () async {
      final channel = FakeShellChannel(cwd: '/home/agent');
      final session = await _session(channel);
      expect(session.cwd, '/home/agent');

      channel.cwd = '/tmp';
      final first = await session.run('cd /tmp');
      expect(first.cwd, '/tmp');
      expect(session.cwd, '/tmp');

      // The next command inherits it — this is what stops the agent
      // hallucinating where it is.
      final second = await session.run('pwd');
      expect(second.cwd, '/tmp');
    });
  });

  group('output cap', () {
    test('truncates the middle while keeping head and tail', () async {
      final channel = FakeShellChannel();
      final session = await _session(channel, outputCapBytes: 1000);

      channel.autoRespond = false;
      final future = session.run('cat huge.log');
      await pumpEventQueue();
      channel.emitStdout('HEAD${'x' * 20000}TAIL');
      channel.emitSentinel(channel.pendingNonce);

      final result = await future;
      expect(result.stdout, startsWith('HEAD'));
      expect(result.stdout, endsWith('TAIL'));
      expect(result.truncated, isNotNull);
      expect(result.truncated!.originalBytes, 20008);
      expect(
        result.truncated!.keptBytes,
        lessThan(result.truncated!.originalBytes),
      );
    });

    test('a capped command does not pollute the next command — the drain runs '
        'to the sentinel so the channel never desynchronizes', () async {
      final channel = FakeShellChannel();
      final session = await _session(channel, outputCapBytes: 500);

      channel.autoRespond = false;
      final first = session.run('cat huge.log');
      await pumpEventQueue();
      channel.emitStdout('FLOOD${'y' * 30000}');
      channel.emitSentinel(channel.pendingNonce);
      await first;

      final second = session.run('echo clean');
      await pumpEventQueue();
      channel.emitStdout('clean\n');
      channel.emitSentinel(channel.pendingNonce);

      final result = await second;
      expect(result.stdout, 'clean\n');
      expect(result.stdout, isNot(contains('y')));
      expect(result.stdout, isNot(contains('FLOOD')));
      expect(result.truncated, isNull);
    });
  });

  group('hang recovery', () {
    test('a command that only answers after Ctrl-C comes back interrupted, '
        'not reset', () async {
      final channel = FakeShellChannel();
      final session = await _session(channel);

      channel.answerOnlyAfterInterrupt = true;
      final result = await session.run(
        'vim',
        timeout: const Duration(milliseconds: 50),
      );

      expect(channel.interruptCount, greaterThanOrEqualTo(1));
      expect(result.interrupted, isTrue);
      expect(result.sessionReset, isFalse);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
      'a command that never answers rebuilds the channel and says so',
      () async {
        final channel = FakeShellChannel(cwd: '/var/www');
        final reopened = <FakeShellChannel>[];
        final session = await _session(channel, reopened: reopened);

        channel.autoRespond = false;
        final result = await session.run(
          'cat /dev/zero',
          timeout: const Duration(milliseconds: 50),
        );

        expect(reopened, hasLength(1), reason: 'the channel was rebuilt');
        expect(result.sessionReset, isTrue);
        expect(
          result.exitCode,
          -1,
          reason: 'no exit code was ever reported by the remote',
        );
        // The agent is told its shell state is gone, but the cwd it was in is
        // restored so it is not also lost.
        expect(session.cwd, '/var/www');
        expect(channel.isClosed, isTrue);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'the session is usable again after a reset',
      () async {
        final channel = FakeShellChannel();
        final reopened = <FakeShellChannel>[];
        final session = await _session(channel, reopened: reopened);

        channel.autoRespond = false;
        await session.run('hang', timeout: const Duration(milliseconds: 50));

        final result = await session.run('echo back');
        expect(result.exitCode, 0);
        expect(result.sessionReset, isFalse);
        expect(
          reopened.single.commandAt(reopened.single.envelopes.length - 1),
          'echo back',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  group('ordering', () {
    test('a second run waits for the first to finish', () async {
      final channel = FakeShellChannel();
      final session = await _session(channel);
      final envelopesAfterInit = channel.envelopes.length;

      channel.autoRespond = false;
      final first = session.run('slow');
      await pumpEventQueue();
      expect(channel.envelopes.length, envelopesAfterInit + 1);

      final second = session.run('fast');
      await pumpEventQueue();
      expect(
        channel.envelopes.length,
        envelopesAfterInit + 1,
        reason: 'the second command must not be written yet',
      );

      channel.emitStdout('first out\n');
      channel.emitSentinel(channel.pendingNonce);
      final firstResult = await first;
      await pumpEventQueue();

      expect(channel.envelopes.length, envelopesAfterInit + 2);
      channel.emitStdout('second out\n');
      channel.emitSentinel(channel.pendingNonce);
      final secondResult = await second;

      expect(firstResult.stdout, 'first out\n');
      expect(secondResult.stdout, 'second out\n');
    });

    test('isBusy is false once the queue drains', () async {
      final channel = FakeShellChannel();
      final session = await _session(channel);

      await session.run('echo done');
      expect(session.isBusy, isFalse);
    });
  });

  group('timeout clamping', () {
    test('a timeout above 600 seconds is clamped', () async {
      final channel = FakeShellChannel();
      final session = await _session(channel);

      // A clamp is not directly observable, so this asserts the practical
      // consequence: an absurd timeout is accepted and the command still runs
      // normally rather than being rejected or waited on forever.
      final result = await session.run(
        'echo ok',
        timeout: const Duration(hours: 5),
      );
      expect(result.exitCode, 0);
    });
  });

  group('interrupt', () {
    test(
      'stops the in-flight command instead of waiting out its timeout',
      () async {
        final channel = FakeShellChannel();
        final reopened = <FakeShellChannel>[];
        final session = await _session(channel, reopened: reopened);

        channel.autoRespond = false;
        final future = session.run('sleep 100');
        await pumpEventQueue();

        // Does not wait behind the run it is interrupting.
        await session.interrupt();
        expect(channel.interruptCount, 1);

        // The signal is only the cheap first try; the channel teardown is what
        // actually stops the command, and the caller is told so rather than
        // being handed a made-up exit code.
        final result = await future;
        expect(result.interrupted, isTrue);
        expect(result.sessionReset, isTrue);
        expect(result.exitCode, -1);
        expect(channel.isClosed, isTrue);
        expect(reopened, hasLength(1));
      },
    );

    test('leaves a usable session behind', () async {
      final channel = FakeShellChannel();
      final reopened = <FakeShellChannel>[];
      final session = await _session(channel, reopened: reopened);

      channel.autoRespond = false;
      final interruptedRun = session.run('sleep 100');
      await pumpEventQueue();
      await session.interrupt();
      await interruptedRun;

      final result = await session.run('echo alive');
      expect(result.exitCode, 0);
      expect(reopened.single.envelopes.last, contains('echo alive'));
    });
  });

  group('close', () {
    test('closes the underlying channel', () async {
      final channel = FakeShellChannel();
      final session = await _session(channel);

      await session.close();
      expect(channel.isClosed, isTrue);
    });
  });
}
