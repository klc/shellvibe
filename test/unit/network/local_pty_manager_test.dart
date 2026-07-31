import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/core/network/local_pty_manager.dart';
import 'package:xterm/xterm.dart';

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
}
