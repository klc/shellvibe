import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/core/network/terminal_mosh_bridge.dart';
import 'package:xterm3/xterm.dart';

import 'mosh_test_doubles.dart';

void main() {
  group('TerminalMoshBridge', () {
    late Terminal terminal;
    late FakeMoshTransport session;
    late TerminalMoshBridge bridge;

    setUp(() {
      terminal = Terminal();
      session = FakeMoshTransport();
      bridge = TerminalMoshBridge(terminal: terminal, session: session);
    });

    tearDown(() async {
      await bridge.dispose(closeSession: false);
      await session.close();
    });

    test('terminal input is sent as UTF-8 bytes', () {
      expect(terminal.onOutput, isNotNull);

      terminal.onOutput!('ls -la\n');

      expect(session.sentBytes, hasLength(1));
      expect(utf8.decode(session.sentBytes.first), equals('ls -la\n'));
    });

    test('host output is written to the terminal', () async {
      session.emitStdout('Hello from mosh!');

      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        terminal.buffer.lines[0].toString(),
        contains('Hello from mosh!'),
      );
    });

    test('a multi-byte character split across datagrams is decoded', () async {
      // 'ğ' is [0xC4, 0x9F]; a screen diff can land on either side of the split.
      session.emitBytes([0xC4]);
      session.emitBytes([0x9F]);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(terminal.buffer.lines[0].toString(), contains('ğ'));
    });

    test('resize forwards columns and rows', () {
      expect(terminal.onResize, isNotNull);

      terminal.onResize!(120, 40, 1024, 768);

      expect(session.resizedColumns, equals(120));
      expect(session.resizedRows, equals(40));
    });

    test('a transport error is surfaced without ending the session', () async {
      session.emitError('datagram failed to decrypt');

      await Future.delayed(const Duration(milliseconds: 50));

      // The notice opens with a newline so it never lands mid-line on whatever
      // the host was drawing, which puts it on the second buffer row.
      expect(
        terminal.buffer.lines[1].toString(),
        contains('datagram failed to decrypt'),
      );
      expect(bridge.isDisposed, isFalse);
    });

    test('server shutdown notifies the owner and disposes', () async {
      var closedCalls = 0;
      final localTerminal = Terminal();
      final localSession = FakeMoshTransport();
      TerminalMoshBridge(
        terminal: localTerminal,
        session: localSession,
        onClosed: () => closedCalls++,
      );

      localSession.serverShutdown();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(closedCalls, equals(1));
      expect(localTerminal.onOutput, isNull);
      expect(localSession.isClosed, isTrue);
    });

    test('dispose detaches callbacks and closes the session', () async {
      await bridge.dispose(closeSession: true);

      expect(bridge.isDisposed, isTrue);
      expect(terminal.onOutput, isNull);
      expect(terminal.onResize, isNull);
      expect(session.isClosed, isTrue);
    });

    test('dispose can leave the session open', () async {
      await bridge.dispose(closeSession: false);

      expect(bridge.isDisposed, isTrue);
      expect(session.isClosed, isFalse);
    });

    test('input after dispose is dropped instead of throwing', () async {
      final onOutput = terminal.onOutput!;
      await bridge.dispose(closeSession: false);

      onOutput('ignored');

      expect(session.sentBytes, isEmpty);
    });
  });
}
