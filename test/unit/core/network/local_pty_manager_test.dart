// Branches on the host OS, so CI runs it on macOS and Windows as well as
// Linux on every pull request (`--tags platform`).
@Tags(['platform'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/coalescing_terminal_writer.dart';
import 'package:shellvibe/core/network/local_pty_manager.dart';
import 'package:xterm3/xterm.dart';

import '../../../support/fake_pty_session.dart';

void main() {
  final manager = LocalPtyManager();

  group('LocalPtyManager.defaultShellArguments', () {
    test('starts known POSIX shells as login shells', () {
      // A GUI app inherits launchd's minimal PATH; only a login shell reads
      // the user's profile and gets Homebrew binaries back on PATH.
      for (final shell in [
        '/bin/zsh',
        '/bin/bash',
        '/bin/sh',
        '/usr/bin/fish',
        '/usr/local/bin/dash',
        '/bin/tcsh',
      ]) {
        expect(manager.defaultShellArguments(shell), [
          '-l',
        ], reason: '$shell should be started as a login shell');
      }
    }, skip: Platform.isWindows);

    test('starts shells that may not understand -l bare', () {
      // `Pty.start` forks and execs, so a rejected flag is not an exception we
      // could catch and retry — the child just dies. Anything not known to
      // take `-l` gets a bare invocation instead of a dead pane.
      for (final shell in [
        '/opt/homebrew/bin/nu',
        '/usr/local/bin/elvish',
        '/usr/bin/rbash',
        '/some/wrapper',
      ]) {
        expect(
          manager.defaultShellArguments(shell),
          isEmpty,
          reason: '$shell is not known to accept -l',
        );
      }
    }, skip: Platform.isWindows);

    test('never adds a login flag on Windows', () {
      expect(manager.defaultShellArguments('powershell.exe'), isEmpty);
    }, skip: !Platform.isWindows);
  });

  group('TerminalLocalPtyBridge Unit Tests', () {
    String renderBuffer(Terminal terminal) => terminal.buffer.lines
        .toList()
        .map((line) => line.toString())
        .join('\n');

    test(
      'renders the numeric exit code when the PTY process finishes',
      () async {
        final terminal = Terminal();
        final session = FakePtySession(exitCode: 7);
        final bridge = TerminalLocalPtyBridge(
          terminal: terminal,
          session: session,
          writerOverride: CoalescingTerminalWriter(
            PacedTerminalWriter(terminal),
            waitForFrame: () async {},
          ),
        );

        session.closeOutput();

        // Let the onDone -> exitCode await continuation flush.
        await pumpEventQueue();

        final rendered = renderBuffer(terminal);
        expect(rendered, contains('[Process exited with code 7]'));
        // Regression: exitCode is a Future<int>; it must be awaited rather than
        // interpolated directly, which previously produced
        // "[Process exited with code Instance of 'Future<int>']".
        expect(rendered, isNot(contains('Instance of')));

        await bridge.dispose();
      },
    );

    test('taps raw PTY bytes before the terminal UTF-8 decoder', () async {
      final terminal = Terminal();
      final session = FakePtySession(exitCode: 0);
      final tapped = <Uint8List>[];
      final bridge = TerminalLocalPtyBridge(
        terminal: terminal,
        session: session,
        outputTap: tapped.add,
        writerOverride: CoalescingTerminalWriter(
          PacedTerminalWriter(terminal),
          waitForFrame: () async {},
        ),
      );

      session.emitOutput(const [0xC3, 0xA7, 0x00, 0xFF]);
      await pumpEventQueue();

      expect(tapped, hasLength(1));
      expect(tapped.single, orderedEquals(const [0xC3, 0xA7, 0x00, 0xFF]));
      expect(terminal.buffer.lines[0].toString(), contains('ç'));

      await bridge.dispose();
    });

    test('a batch is acknowledged once it reaches the paced writer', () async {
      // The credit window lives on the reading isolate: it stops
      // acknowledging the PTY while batches sit unreported, which fills the
      // kernel buffer and blocks the writing process. The bridge's job is
      // just to report each batch it has handed on.
      final terminal = Terminal();
      final session = FakePtySession(exitCode: 0);
      final bridge = TerminalLocalPtyBridge(
        terminal: terminal,
        session: session,
        writerOverride: CoalescingTerminalWriter(
          PacedTerminalWriter(terminal),
          waitForFrame: () async {},
        ),
      );

      for (var i = 0; i < 3; i++) {
        session.emitOutput(List<int>.filled(64, 0x61));
      }
      await pumpEventQueue();

      expect(session.ackCount, equals(3));

      await bridge.dispose();
    });

    test('every batch merged into one hand-over is acknowledged', () async {
      // The bug this pins: batches that arrive between two frames are merged
      // into a single write, so acknowledging once per hand-over returns one
      // credit for several batches. The reader's window drains to nothing and
      // the PTY is never read again — output stops with no freeze to show for
      // it, which is exactly what a run looked like.
      final terminal = Terminal();
      final session = FakePtySession(exitCode: 0);
      final frame = Completer<void>();
      final bridge = TerminalLocalPtyBridge(
        terminal: terminal,
        session: session,
        writerOverride: CoalescingTerminalWriter(
          PacedTerminalWriter(terminal),
          maxWriteChars: 8 * 1024 * 1024,
          waitForFrame: () => frame.future,
        ),
      );

      for (var i = 0; i < 3; i++) {
        session.emitOutput(List<int>.filled(1024, 0x61));
      }
      await pumpEventQueue();
      expect(session.ackCount, equals(0), reason: 'nothing handed over yet');

      frame.complete();
      await pumpEventQueue();

      expect(session.ackCount, equals(3));

      await bridge.dispose();
    });

    test(
      'a batch holding only part of a character is still acknowledged',
      () async {
        // The bug this pins: the decoder emits nothing for a batch that ends
        // mid-character, so a credit counted per decoded chunk was never
        // returned. Four such batches and the reader stopped for good.
        final terminal = Terminal();
        final session = FakePtySession(exitCode: 0);
        final bridge = TerminalLocalPtyBridge(
          terminal: terminal,
          session: session,
          writerOverride: CoalescingTerminalWriter(
            PacedTerminalWriter(terminal),
            waitForFrame: () async {},
          ),
        );

        // 'ş' is C5 9F; a slow writer can hand it over one byte at a time.
        session.emitOutput(const [0xC5]);
        await pumpEventQueue();
        expect(session.ackCount, equals(1));

        session.emitOutput(const [0x9F]);
        await pumpEventQueue();
        expect(session.ackCount, equals(2));
        expect(terminal.buffer.lines[0].toString(), contains('ş'));

        await bridge.dispose();
      },
    );

    test('nothing is acknowledged while a batch is still buffered', () async {
      // A batch that never reaches the writer is a batch the reader must not
      // be told about, or the brake would release on output nobody parsed.
      final terminal = Terminal();
      final session = FakePtySession(exitCode: 0);
      final never = Completer<void>();
      final bridge = TerminalLocalPtyBridge(
        terminal: terminal,
        session: session,
        writerOverride: CoalescingTerminalWriter(
          PacedTerminalWriter(terminal),
          maxWriteChars: 8 * 1024 * 1024,
          waitForFrame: () => never.future,
        ),
      );

      session.emitOutput(List<int>.filled(1024, 0x61));
      await pumpEventQueue();

      expect(session.ackCount, equals(0));

      await bridge.dispose();
    });
  });
}
