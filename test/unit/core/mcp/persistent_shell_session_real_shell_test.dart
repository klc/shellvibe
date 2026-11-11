@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/mcp/shell/persistent_shell_session.dart';
import 'package:shellvibe/core/mcp/shell/shell_channel.dart';

/// The real envelope through a real local shell. [FakeShellChannel] answers
/// every envelope itself, so it cannot show what a shell actually does with
/// `exit`, `set -e`, a stdin reader or a nested shell.
void main() {
  final shells = [
    '/bin/sh',
    for (final name in ['dash', 'bash']) ?_which(name),
  ];

  for (final shell in shells) {
    group(shell, () {
      late PersistentShellSession session;
      late Directory dir;

      setUp(() async {
        dir = await Directory.systemTemp.createTemp('shell_env');
        Future<ShellChannel> open() async =>
            _ProcessShellChannel(await Process.start(shell, const []));
        session = PersistentShellSession(channel: await open(), reopen: open);
        // Also the MCP-8 check: dash reads stdin in blocks, so a channel that
        // still needed an `exec /bin/sh` line would never answer this probe.
        await session.initialize();
      });

      tearDown(() async {
        await session.close();
        await dir.delete(recursive: true);
      });

      Future<Duration> timed(Future<void> Function() body) async {
        final stopwatch = Stopwatch()..start();
        await body();
        return stopwatch.elapsed;
      }

      const fast = Duration(seconds: 5);
      const timeout = Duration(seconds: 20);

      test(
        'exit 0 returns its status at once and the next command runs',
        () async {
          late final dynamic result;
          final took = await timed(() async {
            result = await session.run('echo bye; exit 0', timeout: timeout);
          });
          expect(took, lessThan(fast));
          expect(result.exitCode, 0);
          expect(result.stdout, 'bye\n');
          expect(result.sessionReset, isTrue);
          expect(result.timedOut, isFalse);

          final next = await session.run('echo again', timeout: timeout);
          expect(next.stdout, 'again\n');
          expect(next.sessionReset, isFalse);
        },
      );

      test('set -e; false returns exit 1 at once', () async {
        late final dynamic result;
        final took = await timed(() async {
          result = await session.run('set -e; false', timeout: timeout);
        });
        expect(took, lessThan(fast));
        expect(result.exitCode, 1);
        expect(result.timedOut, isFalse);
      });

      test('cd and export persist across runs', () async {
        final physical = dir.resolveSymbolicLinksSync();
        await session.run('cd "${dir.path}"', timeout: timeout);
        await session.run('export SV_PROBE=kept', timeout: timeout);

        final result = await session.run(
          'echo "\$SV_PROBE"; false',
          timeout: timeout,
        );
        expect(result.stdout, 'kept\n');
        expect(result.exitCode, 1);
        expect(result.cwd, physical);
        expect(session.cwd, physical);
      });

      test('the reported cwd is physical, not an assigned PWD', () async {
        await session.run('cd "${dir.path}"', timeout: timeout);
        final result = await session.run('PWD=/fake', timeout: timeout);
        expect(result.cwd, dir.resolveSymbolicLinksSync());
      });

      test('cat with no arguments returns immediately', () async {
        late final dynamic result;
        final took = await timed(() async {
          result = await session.run('cat', timeout: timeout);
        });
        expect(took, lessThan(fast));
        expect(result.exitCode, 0);
        expect(result.timedOut, isFalse);
      });

      test('a nested shell cannot swallow the commands after it', () async {
        final nested = await session.run('sh', timeout: timeout);
        expect(nested.timedOut, isFalse);
        expect(nested.exitCode, 0);

        final next = await session.run('echo outer', timeout: timeout);
        expect(next.stdout, 'outer\n');
      });
    });
  }

  // What sshd does with the exec request: `$SHELL -c <command>`, with the
  // user's HOME. The marker comes only from the login files.
  group('the login environment', () {
    late Directory home;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('shell_home');
      const profile =
          'echo "Welcome to the test box"\n'
          'export SV_LOGIN_MARK=from-profile\n'
          'PATH="\$HOME/sv-bin:\$PATH"; export PATH\n';
      for (final name in ['.profile', '.bash_profile', '.zprofile']) {
        File('${home.path}/$name').writeAsStringSync(profile);
      }
      File(
        '${home.path}/.cshrc',
      ).writeAsStringSync('setenv SV_LOGIN_MARK from-cshrc\n');
    });

    tearDown(() => home.delete(recursive: true));

    final loginShells = {
      for (final name in ['bash', 'dash', 'zsh', 'tcsh', 'csh']) ?_which(name),
    };

    for (final login in loginShells) {
      test('$login: the session sees what the login files set', () async {
        Future<ShellChannel> open() async => _ProcessShellChannel(
          await Process.start(
            login,
            ['-c', PersistentShellSession.remoteCommand],
            environment: {'SHELL': login, 'HOME': home.path},
          ),
        );
        final session = PersistentShellSession(
          channel: await open(),
          reopen: open,
        );
        addTearDown(session.close);
        // The profile's greeting lands before the probe and must not stop it.
        await session.initialize();

        final result = await session.run(
          r'echo "$SV_LOGIN_MARK"; echo "$PATH"; echo "$0"',
          timeout: const Duration(seconds: 20),
        );
        final [mark, path, shell, ...] = result.stdout.split('\n');
        final csh = login.endsWith('csh');
        expect(mark, csh ? 'from-cshrc' : 'from-profile');
        if (!csh) expect(path, startsWith('${home.path}/sv-bin:'));
        expect(shell, '/bin/sh');
      });
    }
  });
}

String? _which(String name) {
  final result = Process.runSync('which', [name]);
  final path = (result.stdout as String).trim();
  return result.exitCode == 0 && path.isNotEmpty ? path : null;
}

/// [ShellChannel] over a local shell process, standing in for an SSH exec
/// channel running `/bin/sh`.
class _ProcessShellChannel implements ShellChannel {
  _ProcessShellChannel(this._process) {
    done = _process.exitCode.then((code) {
      _closed = true;
      return code;
    });
    // Writing to a shell that already exited fails the sink, not the write.
    unawaited(_process.stdin.done.catchError((Object _) {}));
  }

  final Process _process;
  bool _closed = false;

  @override
  late final Future<int?> done;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  bool get isClosed => _closed;

  @override
  void write(List<int> data) {
    if (!_closed) _process.stdin.add(data);
  }

  @override
  void sendInterrupt() {}

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _process.kill();
    await _process.exitCode;
  }
}
