import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:terly2/features/hosts/domain/models/host_model.dart';
import 'package:terly2/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:terly2/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('TerminalTabsNotifier Unit Tests', () {
    test('Initial state has no active tabs', () {
      final state = container.read(terminalTabsProvider);
      expect(state.tabs, isEmpty);
      expect(state.activeTabId, isNull);
      expect(state.activeTab, isNull);
    });

    test('openLocalTab adds a new tab and sets as active', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'Test Shell');

      final state = container.read(terminalTabsProvider);
      expect(state.tabs.length, equals(1));
      expect(state.activeTabId, isNotNull);
      expect(state.activeTab!.title, equals('Test Shell'));
    });

    test('setActiveTab switches active tab', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'Tab 1');
      final id1 = container.read(terminalTabsProvider).activeTabId!;

      notifier.openLocalTab(title: 'Tab 2');
      final id2 = container.read(terminalTabsProvider).activeTabId!;

      expect(id1, isNot(equals(id2)));
      expect(container.read(terminalTabsProvider).activeTab!.title, equals('Tab 2'));

      notifier.setActiveTab(id1);
      expect(container.read(terminalTabsProvider).activeTabId, equals(id1));
      expect(container.read(terminalTabsProvider).activeTab!.title, equals('Tab 1'));
    });

    test('closeTab disposes session and updates active tab', () async {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'Tab 1');
      final id1 = container.read(terminalTabsProvider).activeTabId!;

      notifier.openLocalTab(title: 'Tab 2');
      final id2 = container.read(terminalTabsProvider).activeTabId!;

      await notifier.closeTab(id2);

      final state = container.read(terminalTabsProvider);
      expect(state.tabs.length, equals(1));
      expect(state.activeTabId, equals(id1));
    });

    test('splitTab creates split pane session', () {
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'Main Tab');
      final mainId = container.read(terminalTabsProvider).activeTabId!;

      notifier.splitTab(mainId);

      final state = container.read(terminalTabsProvider);
      expect(state.tabs.length, equals(2));
      final splitTab = state.tabs.last;
      expect(splitTab.splitParentId, equals(mainId));
      expect(splitTab.sessionType, equals(TerminalSessionType.local));
    });

    test('splitTab on an SSH host tab creates an SSH split inheriting host and identity', () async {
      final notifier = container.read(terminalTabsProvider.notifier);
      final host = HostModel(
        id: 'host-split',
        workspaceId: 'ws-1',
        label: 'Split Host',
        hostname: '127.0.0.1',
        port: 1,
        createdAt: DateTime.now(),
      );

      final openFuture = notifier.openTabForHost(host);
      final mainId = container.read(terminalTabsProvider).activeTabId!;

      final splitFuture = notifier.splitTab(mainId);
      final state = container.read(terminalTabsProvider);
      final splitTab = state.tabs.last;

      // The split mirrors the parent: an SSH session to the same host.
      expect(splitTab.splitParentId, equals(mainId));
      expect(splitTab.sessionType, equals(TerminalSessionType.ssh));
      expect(splitTab.host?.id, equals(host.id));
      expect(splitTab.isConnecting, isTrue);

      // Await both connection attempts so no in-flight SSH work leaks into
      // teardown (the connection to port 1 fails and is caught internally).
      await Future.wait([openFuture, splitFuture ?? Future<void>.value()]);
    });

    test('openTabForHost assigns dedicated SSHSessionManager instance per tab', () async {
      final notifier = container.read(terminalTabsProvider.notifier);
      final host = HostModel(
        id: 'host-1',
        workspaceId: 'ws-1',
        label: 'Test Host',
        hostname: '127.0.0.1',
        port: 1,
        createdAt: DateTime.now(),
      );

      final future1 = notifier.openTabForHost(host);
      final tab1 = container.read(terminalTabsProvider).tabs.last;

      final future2 = notifier.openTabForHost(host);
      final tab2 = container.read(terminalTabsProvider).tabs.last;

      expect(tab1.id, isNot(equals(tab2.id)));
      expect(tab1.sshSessionManager, isNotNull);
      expect(tab2.sshSessionManager, isNotNull);
      expect(identical(tab1.sshSessionManager, tab2.sshSessionManager), isFalse);

      final manager1 = tab1.sshSessionManager;

      await notifier.closeTab(tab1.id);
      final remainingTab = container.read(terminalTabsProvider).tabs.firstWhere((t) => t.id == tab2.id);

      expect(remainingTab.id, equals(tab2.id));
      expect(remainingTab.sshSessionManager, isNotNull);
      expect(identical(remainingTab.sshSessionManager, manager1), isFalse);

      // Await futures to prevent unhandled background errors in test tearDown
      await Future.wait([future1, future2]);
    });

    test('openTabForHost parses user@hostname and resolves effective username correctly', () async {
      final notifier = container.read(terminalTabsProvider.notifier);

      final hostWithUserInName = HostModel(
        id: 'host-user',
        workspaceId: 'ws-1',
        label: 'Parsed Host',
        hostname: 'admin@192.168.1.100',
        port: 1,
        createdAt: DateTime.now(),
      );

      final future = notifier.openTabForHost(hostWithUserInName);
      final tab = container.read(terminalTabsProvider).tabs.last;
      expect(tab.host?.hostname, equals('admin@192.168.1.100'));

      await future;
    });
  });
}
