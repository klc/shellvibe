import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/core/network/terminal_ssh_bridge.dart';
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
  group('TerminalSSHBridge Unit Tests', () {
    late Terminal terminal;
    late FakeSSHSession session;
    late TerminalSSHBridge bridge;

    setUp(() {
      terminal = Terminal();
      session = FakeSSHSession();
      bridge = TerminalSSHBridge(terminal: terminal, session: session);
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
