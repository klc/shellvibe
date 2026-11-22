// Drives a real PTY, so it only runs where one exists; CI runs it on macOS and
// Linux on every pull request (`--tags platform`).
@Tags(['platform'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/pty_session.dart';

void main() {
  // flutter_pty2's build hook builds and bundles its native library for
  // `flutter test` as it does for an app, so nothing is compiled here.

  test(
    'a paste larger than the tty input queue reaches the process',
    () async {
      // Tags the child so a deadlocked run can still be killed: the reader
      // isolate stuck in a blocking write only returns once the child dies.
      final tag = 'pty-session-test-${DateTime.now().microsecondsSinceEpoch}';
      addTearDown(() => Process.run('pkill', ['-f', tag]));

      final session = await PtyIsolateSession.start(
        PtySessionConfig(
          executable: '/bin/sh',
          arguments: ['-c', 'cat # $tag'],
          workingDirectory: null,
          environment: Platform.environment,
          rows: 24,
          columns: 80,
        ),
      );

      const marker = 'END-OF-PASTE';
      final seen = Completer<void>();
      final received = StringBuffer();
      // Consumed and acknowledged batch by batch, as TerminalLocalPtyBridge
      // does.
      final subscription = session.output.listen((batch) {
        received.write(utf8.decode(batch, allowMalformed: true));
        session.acknowledge();
        if (!seen.isCompleted && received.toString().contains(marker)) {
          seen.complete();
        }
      });

      // 64 KiB of short lines in one write, far past the ~1 KiB the tty
      // accepts before the writer has to wait for the process to read.
      final line = '${'x' * 63}\n';
      final paste = Uint8List.fromList(utf8.encode(line * 1024));
      session.write(paste);
      session.write(Uint8List.fromList(utf8.encode('$marker\n')));

      await expectLater(
        seen.future.timeout(const Duration(seconds: 5)),
        completes,
      );

      await subscription.cancel();
      await session.dispose();
    },
    timeout: const Timeout(Duration(seconds: 20)),
    skip: Platform.isWindows,
  );

  test(
    'a disposed session gives its native file descriptors back',
    () async {
      // The bug this pins: dispose killed the process and exited the reader
      // isolate without destroying the PTY handle, and the plugin closes the
      // master fd and its wake pipe only in destroy. Every closed tab leaked
      // three descriptors until the app hit its open-file limit.
      Future<int> openFds() async {
        if (Platform.isLinux) {
          return Directory('/proc/self/fd').listSync().length;
        }
        // macOS's /dev/fd cannot be listed from Dart.
        final lsof = await Process.run('lsof', ['-p', '$pid']);
        return (lsof.stdout as String).trim().split('\n').length;
      }

      final before = await openFds();
      const sessions = 5;
      for (var i = 0; i < sessions; i++) {
        final session = await PtyIsolateSession.start(
          PtySessionConfig(
            executable: '/bin/sh',
            arguments: const ['-c', 'sleep 30'],
            workingDirectory: null,
            environment: Platform.environment,
            rows: 24,
            columns: 80,
          ),
        );
        // Listened to as the bridge does; dispose waits for the output to
        // be done.
        final output = session.output.listen((_) => session.acknowledge());
        await session.dispose();
        await output.cancel();
      }

      expect(await openFds() - before, lessThan(sessions));
    },
    timeout: const Timeout(Duration(seconds: 20)),
    skip: Platform.isWindows,
  );

  test(
    'exit is reported while a background job still holds the terminal',
    () async {
      // `done` waits for the PTY's output to end, and a job left running in
      // the background keeps the terminal open. The tab must still learn that
      // its shell exited.
      final tag = 'pty-session-test-${DateTime.now().microsecondsSinceEpoch}';
      addTearDown(() => Process.run('pkill', ['-f', tag]));

      final session = await PtyIsolateSession.start(
        PtySessionConfig(
          executable: '/bin/sh',
          arguments: ['-c', 'sleep 30 & exit 3 # $tag'],
          workingDirectory: null,
          environment: Platform.environment,
          rows: 24,
          columns: 80,
        ),
      );
      final output = session.output.listen((_) => session.acknowledge());

      expect(await session.exitCode.timeout(const Duration(seconds: 5)), 3);

      await output.cancel();
      await session.dispose();
    },
    timeout: const Timeout(Duration(seconds: 20)),
    skip: Platform.isWindows,
  );

  test(
    'dispose hangs the shell up before it is killed',
    () async {
      // What a closing terminal sends. Without it a shell is SIGKILLed and
      // never saves its history or hangs up its jobs.
      final dir = await Directory.systemTemp.createTemp('pty_session_hup');
      addTearDown(() => dir.delete(recursive: true));
      final marker = File('${dir.path}/hup');
      final ready = File('${dir.path}/ready');

      final session = await PtyIsolateSession.start(
        PtySessionConfig(
          executable: '/bin/sh',
          arguments: [
            '-c',
            'trap "echo hup > ${marker.path}; exit 0" HUP; '
                ': > ${ready.path}; '
                'while :; do sleep 0.05; done',
          ],
          workingDirectory: null,
          environment: Platform.environment,
          rows: 24,
          columns: 80,
        ),
      );
      final output = session.output.listen((_) => session.acknowledge());
      for (var i = 0; i < 100 && !ready.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(ready.existsSync(), isTrue, reason: 'the shell never started');

      await session.dispose();
      await output.cancel();

      expect(marker.existsSync(), isTrue);
    },
    timeout: const Timeout(Duration(seconds: 20)),
    skip: Platform.isWindows,
  );
}
