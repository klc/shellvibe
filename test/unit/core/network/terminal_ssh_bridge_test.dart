import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/coalescing_terminal_writer.dart';
import 'package:shellvibe/core/network/terminal_ssh_bridge.dart';
import 'package:xterm3/xterm.dart';

/// Fake implementation of [SSHSession] for testing stream bridge behavior.
class FakeSSHSession implements SSHSession {
  final _stdinController = StreamController<Uint8List>();
  final _stdoutController = StreamController<Uint8List>();
  final _stderrController = StreamController<Uint8List>();

  final List<Uint8List> writtenBytes = [];
  int? resizedWidth;
  int? resizedHeight;
  bool isClosed = false;

  /// Makes [resizeTerminal] throw, exercising the bridge's error path.
  bool throwOnResize = false;

  @override
  StreamSink<Uint8List> get stdin => _stdinController.sink;

  @override
  Stream<Uint8List> get stdout => _stdoutController.stream;

  @override
  Stream<Uint8List> get stderr => _stderrController.stream;

  @override
  void write(Uint8List data) {
    writtenBytes.add(data);
  }

  @override
  void resizeTerminal(int width, int height, [int pixelWidth = 0, int pixelHeight = 0]) {
    if (throwOnResize) throw StateError('resize refused');
    resizedWidth = width;
    resizedHeight = height;
  }

  @override
  void close() {
    isClosed = true;
    _stdinController.close();
    _stdoutController.close();
    _stderrController.close();
  }

  void emitBytes(Uint8List bytes) {
    _stdoutController.add(bytes);
  }

  void emitStdout(String data) {
    _stdoutController.add(Uint8List.fromList(utf8.encode(data)));
  }

  void emitStderr(String data) {
    _stderrController.add(Uint8List.fromList(utf8.encode(data)));
  }

  void closeStdout() {
    _stdoutController.close();
  }

  void closeStderr() {
    _stderrController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  _pacedWriteTests();

  group('TerminalSSHBridge Unit Tests', () {
    late Terminal terminal;
    late FakeSSHSession session;
    late TerminalSSHBridge bridge;

    setUp(() {
      terminal = Terminal();
      session = FakeSSHSession();
      bridge = TerminalSSHBridge(
        terminal: terminal,
        session: session,
        // No frame pipeline here, so the write stack hands over off a
        // resolved future rather than a frame that never comes.
        writerOverride: CoalescingTerminalWriter(
          PacedTerminalWriter(terminal),
          waitForFrame: () async {},
        ),
      );
    });

    tearDown(() async {
      await bridge.dispose(closeSession: false);
      session.close();
    });

    test('terminal.onOutput writes encoded UTF-8 bytes to session', () {
      expect(terminal.onOutput, isNotNull);

      // Simulate user typing in xterm Terminal
      terminal.onOutput!('ls -la\n');

      expect(session.writtenBytes, hasLength(1));
      expect(utf8.decode(session.writtenBytes.first), equals('ls -la\n'));
    });

    test('session.stdout stream writes text to terminal', () async {
      final completer = Completer<void>();

      // Listen for buffer updates or tick event
      session.emitStdout('Hello Remote Server!');

      await Future.delayed(const Duration(milliseconds: 50));

      expect(terminal.buffer.lines[0].toString(), contains('Hello Remote Server!'));
      completer.complete();
    });

    test('session.stderr stream writes text to terminal', () async {
      session.emitStderr('Permission denied\n');

      await Future.delayed(const Duration(milliseconds: 50));

      expect(terminal.buffer.lines[0].toString(), contains('Permission denied'));
    });

    test('terminal.onResize invokes session.resizeTerminal with cols and rows', () {
      expect(terminal.onResize, isNotNull);

      terminal.onResize!(120, 40, 1024, 768);

      expect(session.resizedWidth, equals(120));
      expect(session.resizedHeight, equals(40));
    });

    test('dispose cancels subscriptions and detaches terminal callbacks', () async {
      await bridge.dispose(closeSession: true);

      expect(bridge.isDisposed, isTrue);
      expect(terminal.onOutput, isNull);
      expect(terminal.onResize, isNull);
      expect(session.isClosed, isTrue);
    });

    test('UTF-8 decoder handles multi-byte split Turkish characters across chunks', () async {
      // 'ğ' in UTF-8 is [0xC4, 0x9F]
      session.emitBytes(Uint8List.fromList([0xC4]));
      await Future.delayed(const Duration(milliseconds: 20));
      session.emitBytes(Uint8List.fromList([0x9F]));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(terminal.buffer.lines[0].toString(), contains('ğ'));
    });

    test('onDone writes session closed message and disposes bridge', () async {
      session.emitStdout('stdout end');
      session.close();

      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        terminal.buffer.getText(),
        contains('[Session closed / Process exited]'),
      );
      expect(bridge.isDisposed, isTrue);
    });

    test('stdout closure does not dispose bridge until stderr also closes', () async {
      session.emitStdout('stdout message');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(terminal.buffer.getText(), contains('stdout message'));

      // Close stdout stream only
      session.closeStdout();
      await Future.delayed(const Duration(milliseconds: 50));

      // Bridge should NOT be disposed yet
      expect(bridge.isDisposed, isFalse);

      // Stderr should still write to terminal after stdout is closed
      session.emitStderr('stderr message after stdout closed');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(terminal.buffer.getText(), contains('stderr message after stdout closed'));

      // Close stderr stream as well
      session.closeStderr();
      await Future.delayed(const Duration(milliseconds: 50));

      // Now bridge should be disposed after both streams are closed
      expect(bridge.isDisposed, isTrue);
      expect(
        terminal.buffer.getText(),
        contains('[Session closed / Process exited]'),
      );
    });
  });
}

/// Records every write the bridge makes, then forwards it so the terminal
/// still behaves normally.
class SpyPacedWriter extends PacedTerminalWriter {
  SpyPacedWriter(super.terminal);

  final List<String> writes = [];
  int flushCount = 0;

  @override
  void write(String data) {
    writes.add(data);
    super.write(data);
  }

  @override
  void flush() {
    flushCount++;
    super.flush();
  }
}

/// Regression cover for the paced-write path.
///
/// Before this, every stdout chunk went straight to `Terminal.write`, so a
/// burst was parsed inline and held the UI isolate for the whole burst — a
/// `cat` of a large file or a terminal benchmark froze the window hard enough
/// for macOS to show the spinning wait cursor.
///
/// What is pinned here is the wiring, not the pacing itself: that every write
/// the bridge makes goes through the writer. Pacing only engages once chunks
/// queue faster than they drain, which a StreamController cannot reproduce
/// (it delivers each event in its own turn, so each chunk drains before the
/// next arrives). The yielding behaviour is xterm3's and is covered there.
/// Coalescing is visible in one place: chunks emitted before the batch is
/// handed over arrive as one write. Its own test covers the behaviour.
/// A revert to a direct `terminal.write` fails these tests.
void _pacedWriteTests() {
  group('TerminalSSHBridge paced writes', () {
    late Terminal terminal;
    late FakeSSHSession session;
    late TerminalSSHBridge bridge;
    late SpyPacedWriter writer;

    setUp(() {
      terminal = Terminal();
      session = FakeSSHSession();
      writer = SpyPacedWriter(terminal);
      bridge = TerminalSSHBridge(
        terminal: terminal,
        session: session,
        // Both stages hand over on the next frame, which never comes here, so
        // the test drives them off a resolved future instead.
        writerOverride: CoalescingTerminalWriter(
          writer,
          waitForFrame: () async {},
        ),
      );
    });

    tearDown(() async {
      await bridge.dispose(closeSession: false);
      session.close();
    });

    test('stdout goes through the paced writer', () async {
      session.emitStdout('remote output');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(writer.writes, contains('remote output'));
      expect(terminal.buffer.lines[0].toString(), contains('remote output'));
    });

    test('stderr goes through the same writer as stdout', () async {
      session.emitStdout('out ');
      session.emitStderr('err');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // One writer for both streams keeps their interleaving intact. Both
      // chunks were emitted before the batch was handed over, so they arrive
      // as a single write — which is the ordering guarantee, stated more
      // strongly than two separate writes would state it.
      expect(writer.writes, equals(['out err']));
    });

    test('status messages queue behind output instead of jumping ahead',
        () async {
      session.throwOnResize = true;
      session.emitStdout('output-first');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      bridge.resizeTerminal(80, 24, 0, 0);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // The error text went through the writer, so it cannot overtake output
      // the remote sent earlier and still sitting in the queue.
      expect(writer.writes.first, equals('output-first'));
      expect(writer.writes.last, contains('SSH resize error'));
    });

    test('dispose flushes the writer so queued output is not dropped',
        () async {
      session.emitStdout('kept');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await bridge.dispose(closeSession: false);

      expect(writer.flushCount, greaterThan(0));
      expect(terminal.buffer.lines[0].toString(), contains('kept'));
    });
  });
}
