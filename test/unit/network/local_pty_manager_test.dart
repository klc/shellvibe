// Branches on the host OS, so CI runs it on macOS and Windows as well as
// Linux on every pull request (`--tags platform`).
@Tags(['platform'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellvibe/core/network/pty_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/local_pty_manager.dart';
import 'package:xterm3/xterm.dart';
import 'package:shellvibe/core/network/coalescing_terminal_writer.dart';

/// Fake implementation of [Pty] for testing the [TerminalLocalPtyBridge]
/// without spawning a real pseudo-terminal process.
class FakePtySession implements PtySession {
  FakePtySession({required int exitCode}) {
    _exitCodeCompleter.complete(exitCode);
  }

  final _outputController = StreamController<Uint8List>();
  final _exitCodeCompleter = Completer<int>();

  @override
  Stream<Uint8List> get output => _outputController.stream;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  @override
  void write(Uint8List data) {}

  @override
  void resize(int rows, int cols) {}

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  int ackCount = 0;

  @override
  void acknowledge() => ackCount++;

  @override
  Future<void> dispose({bool kill = true}) async => closeOutput();

  /// Closes the output stream to simulate the PTY process finishing.
  void closeOutput() {
    _outputController.close();
  }

  void emitOutput(List<int> bytes) {
    _outputController.add(Uint8List.fromList(bytes));
  }
}

void main() {
  group('LocalPtyManager Unit Tests', () {
    late LocalPtyManager ptyManager;

    setUp(() {
      ptyManager = LocalPtyManager();
    });

    test(
      'isSupportedPlatform returns false on iOS and true on desktop/Android',
      () {
        if (Platform.isIOS) {
          expect(ptyManager.isSupportedPlatform, isFalse);
        } else {
          expect(ptyManager.isSupportedPlatform, isTrue);
        }
      },
    );

    test('getDefaultShell returns a non-empty shell command', () {
      final shell = ptyManager.getDefaultShell();
      expect(shell, isNotEmpty);
      if (Platform.isWindows) {
        expect(shell, contains('powershell'));
      }
    });

    test(
      'startAndBridge handles iOS fallback message gracefully if on iOS',
      () {
        if (Platform.isIOS) {
          final terminal = Terminal();
          final bridge = ptyManager.startAndBridge(terminal);

          expect(bridge, isNull);
          expect(
            terminal.buffer.lines[0].toString(),
            contains('iOS Sandbox Restriction'),
          );
        }
      },
    );
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
