import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/core/network/local_pty_manager.dart';
import 'package:xterm3/xterm.dart';

/// Fake implementation of [Pty] for testing the [TerminalLocalPtyBridge]
/// without spawning a real pseudo-terminal process.
class FakePty implements Pty {
  FakePty({required int exitCode}) {
    _exitCodeCompleter.complete(exitCode);
  }

  final _outputController = StreamController<Uint8List>();
  final _exitCodeCompleter = Completer<int>();

  @override
  final String executable = '/bin/sh';

  @override
  final List<String> arguments = const [];

  @override
  Stream<Uint8List> get output => _outputController.stream;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  @override
  int get pid => 1234;

  @override
  void write(Uint8List data) {}

  @override
  void resize(int rows, int cols) {}

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  void ackRead() {}

  /// Closes the output stream to simulate the PTY process finishing.
  void closeOutput() {
    _outputController.close();
  }
}

void main() {
  group('LocalPtyManager Unit Tests', () {
    late LocalPtyManager ptyManager;

    setUp(() {
      ptyManager = LocalPtyManager();
    });

    test('isSupportedPlatform returns false on iOS and true on desktop/Android', () {
      if (Platform.isIOS) {
        expect(ptyManager.isSupportedPlatform, isFalse);
      } else {
        expect(ptyManager.isSupportedPlatform, isTrue);
      }
    });

    test('getDefaultShell returns a non-empty shell command', () {
      final shell = ptyManager.getDefaultShell();
      expect(shell, isNotEmpty);
      if (Platform.isWindows) {
        expect(shell, contains('powershell'));
      }
    });

    test('startAndBridge handles iOS fallback message gracefully if on iOS', () {
      if (Platform.isIOS) {
        final terminal = Terminal();
        final bridge = ptyManager.startAndBridge(terminal);

        expect(bridge, isNull);
        expect(terminal.buffer.lines[0].toString(), contains('iOS Sandbox Restriction'));
      }
    });
  });

  group('TerminalLocalPtyBridge Unit Tests', () {
    String renderBuffer(Terminal terminal) =>
        terminal.buffer.lines.toList().map((line) => line.toString()).join('\n');

    test('renders the numeric exit code when the PTY process finishes', () async {
      final terminal = Terminal();
      final pty = FakePty(exitCode: 7);
      final bridge = TerminalLocalPtyBridge(terminal: terminal, pty: pty);

      pty.closeOutput();

      // Let the onDone -> exitCode await continuation flush.
      await pumpEventQueue();

      final rendered = renderBuffer(terminal);
      expect(rendered, contains('[Process exited with code 7]'));
      // Regression: exitCode is a Future<int>; it must be awaited rather than
      // interpolated directly, which previously produced
      // "[Process exited with code Instance of 'Future<int>']".
      expect(rendered, isNot(contains('Instance of')));

      await bridge.dispose();
    });
  });
}
