import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
      final state = container.read(terminalTabsNotifierProvider);
      expect(state.tabs, isEmpty);
      expect(state.activeTabId, isNull);
      expect(state.activeTab, isNull);
    });

    test('openLocalTab adds a new tab and sets as active', () {
      final notifier = container.read(terminalTabsNotifierProvider.notifier);

      notifier.openLocalTab(title: 'Test Shell');

      final state = container.read(terminalTabsNotifierProvider);
      expect(state.tabs.length, equals(1));
      expect(state.activeTabId, isNotNull);
      expect(state.activeTab!.title, equals('Test Shell'));
    });

    test('setActiveTab switches active tab', () {
      final notifier = container.read(terminalTabsNotifierProvider.notifier);

      notifier.openLocalTab(title: 'Tab 1');
      final id1 = container.read(terminalTabsNotifierProvider).activeTabId!;

      notifier.openLocalTab(title: 'Tab 2');
      final id2 = container.read(terminalTabsNotifierProvider).activeTabId!;

      expect(id1, isNot(equals(id2)));
      expect(container.read(terminalTabsNotifierProvider).activeTab!.title, equals('Tab 2'));

      notifier.setActiveTab(id1);
      expect(container.read(terminalTabsNotifierProvider).activeTabId, equals(id1));
      expect(container.read(terminalTabsNotifierProvider).activeTab!.title, equals('Tab 1'));
    });

    test('closeTab disposes session and updates active tab', () async {
      final notifier = container.read(terminalTabsNotifierProvider.notifier);

      notifier.openLocalTab(title: 'Tab 1');
      final id1 = container.read(terminalTabsNotifierProvider).activeTabId!;

      notifier.openLocalTab(title: 'Tab 2');
      final id2 = container.read(terminalTabsNotifierProvider).activeTabId!;

      await notifier.closeTab(id2);

      final state = container.read(terminalTabsNotifierProvider);
      expect(state.tabs.length, equals(1));
      expect(state.activeTabId, equals(id1));
    });

    test('splitTab creates split pane session', () {
      final notifier = container.read(terminalTabsNotifierProvider.notifier);

      notifier.openLocalTab(title: 'Main Tab');
      final mainId = container.read(terminalTabsNotifierProvider).activeTabId!;

      notifier.splitTab(mainId);

      final state = container.read(terminalTabsNotifierProvider);
      expect(state.tabs.length, equals(2));
      final splitTab = state.tabs.last;
      expect(splitTab.splitParentId, equals(mainId));
    });
  });
}
