import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/core/network/mosh_session_manager.dart';
import 'package:terly2/core/network/terminal_mosh_bridge.dart';
import 'package:terly2/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:xterm3/xterm.dart';

import '../../network/mosh_test_doubles.dart';

void main() {
  group('TerminalTabSession with a Mosh transport', () {
    late Terminal terminal;
    late FakeMoshTransport transport;
    late TerminalTabSession tab;

    setUp(() {
      terminal = Terminal();
      transport = FakeMoshTransport();
      tab = TerminalTabSession(
        id: 'tab-1',
        title: 'mosh host',
        sessionType: TerminalSessionType.ssh,
        terminal: terminal,
      );
      tab.moshBridge = TerminalMoshBridge(
        terminal: terminal,
        session: transport,
      );
    });

    test('isMosh reflects which bridge carries the shell', () {
      expect(tab.isMosh, isTrue);

      tab.moshBridge = null;
      expect(tab.isMosh, isFalse);
    });

    test('resizeTerminal reaches the Mosh session', () {
      tab.resizeTerminal(140, 45);

      expect(transport.resizedColumns, equals(140));
      expect(transport.resizedRows, equals(45));
    });

    test('dispose closes the Mosh session and its manager', () async {
      final manager = MoshSessionManager();
      tab.moshSessionManager = manager;
      tab.moshLinkSub = manager.linkStates.listen((_) {});

      await tab.dispose();

      expect(tab.moshBridge, isNull);
      expect(tab.moshSessionManager, isNull);
      expect(tab.moshLinkSub, isNull);
      expect(transport.isClosed, isTrue);
    });

    test('a tab with no Mosh session disposes cleanly', () async {
      final plainTerminal = Terminal();
      final plainTab = TerminalTabSession(
        id: 'tab-2',
        title: 'local',
        sessionType: TerminalSessionType.local,
        terminal: plainTerminal,
      );

      await plainTab.dispose();

      expect(plainTab.moshBridge, isNull);
      expect(plainTab.moshSessionManager, isNull);
    });
  });
}
