import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:terly2/core/utils/platform_capabilities.dart';
import 'package:terly2/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:terly2/features/terminal/presentation/views/terminal_tab_view.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/providers/database_providers.dart';
import 'package:xterm3/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    debugPlatformCapabilitiesOverride = null;
    await db.close();
  });

  Widget createWidgetUnderTest() {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.dark(),
          brightness: Brightness.dark,
        ),
        child: const MaterialApp(home: TerminalTabView()),
      ),
    );
  }

  group('TerminalTabView Widget Tests', () {
    testWidgets('Renders empty state when no tabs are active', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('No Active Terminal Sessions'), findsOneWidget);
      expect(find.byKey(const Key('empty_open_local_button')), findsOneWidget);
      expect(find.byKey(const Key('empty_select_host_button')), findsOneWidget);
    });

    testWidgets('Does not expose or trigger a local shell on mobile', (
      tester,
    ) async {
      debugPlatformCapabilitiesOverride = TargetPlatform.android;
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.dark(),
              brightness: Brightness.dark,
            ),
            child: const MaterialApp(home: TerminalTabView()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('empty_open_local_button')), findsNothing);
      expect(
        find.text('Select a remote SSH server to connect.'),
        findsOneWidget,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(container.read(terminalTabsProvider).tabs, isEmpty);
    });

    testWidgets(
      'Shows a Device Link sharing indicator with a disconnect control',
      (tester) async {
        final container = ProviderContainer(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: ShadTheme(
              data: ShadThemeData(
                colorScheme: const ShadSlateColorScheme.dark(),
                brightness: Brightness.dark,
              ),
              child: const MaterialApp(home: TerminalTabView()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.byKey(const Key('empty_open_local_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final shared = container.read(terminalTabsProvider).tabs.single;
        expect(
          find.byKey(Key('device_link_attachment_${shared.id}')),
          findsNothing,
          reason: 'An unattached session must not claim to be shared',
        );

        // Byte traffic from a phone runs code on this machine, so an attached
        // session has to be visible on the desktop and cuttable from there.
        shared.attachDeviceLink(deviceId: 'phone-1', columns: 52, rows: 30);
        // Opening a second tab republishes the tab list, which is how the
        // real attach path also reaches the status bar.
        await tester.tap(find.byKey(const Key('new_tab_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('new_tab_menu_local')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(Key('device_link_attachment_${shared.id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(Key('device_link_disconnect_${shared.id}')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Device Link · ${shared.title}'),
          findsOneWidget,
        );

        // The container outlives the widget tree here, so dispose it inside
        // the test body: the keep-alive tab notifier owns the terminal
        // sessions and only releases their timers when it is disposed.
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.pumpAndSettle();
      },
    );

    testWidgets('Opens local shell tab on Open Local Shell button tap', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('empty_open_local_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Local Shell'), findsWidgets);
      expect(find.byKey(const Key('new_tab_button')), findsOneWidget);
    });
    testWidgets('Tab bar actions collapse into an overflow menu on a phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('empty_open_local_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Only "+" and the overflow trigger stay inline; the split/template
      // buttons live behind the menu.
      expect(find.byKey(const Key('new_tab_button')), findsOneWidget);
      expect(find.byKey(const Key('tab_bar_overflow_button')), findsOneWidget);
      expect(find.byKey(const Key('split_vertical_button')), findsNothing);

      await tester.tap(find.byKey(const Key('tab_bar_overflow_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('split_vertical_button')), findsOneWidget);
      expect(find.byKey(const Key('run_template_button')), findsOneWidget);
    });

    testWidgets('Opens new tab menu on new tab button tap', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('new_tab_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('new_tab_menu_local')), findsOneWidget);
      expect(find.byKey(const Key('new_tab_menu_host')), findsOneWidget);
    });

    testWidgets('Closes active tab on close button tap', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('empty_open_local_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Local Shell'), findsWidgets);

      final closeIcon = find.byIcon(LucideIcons.x).first;
      await tester.tap(closeIcon);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('empty_open_local_button')), findsOneWidget);
    });

    testWidgets('Focus moves to the newly opened terminal pane', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TerminalTabView)),
      );

      // First terminal from the empty state.
      await tester.tap(find.byKey(const Key('empty_open_local_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final tab1 = container.read(terminalTabsProvider).activeTabId;
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'terminal_$tab1',
        reason: 'keystrokes must land in the newly opened terminal',
      );

      // A second terminal opened while one is already running must also take
      // focus (element reuse alone never re-fires autofocus).
      await tester.tap(find.byKey(const Key('new_tab_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new_tab_menu_local')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final tab2 = container.read(terminalTabsProvider).activeTabId;
      expect(tab1, isNot(equals(tab2)));
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'terminal_$tab2',
        reason: 'focus must follow the active tab switch',
      );
    });

    testWidgets('Vertical and Horizontal split buttons create split sessions without extra top tab bar entries', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Open initial local tab
      await tester.tap(find.byKey(const Key('empty_open_local_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('split_vertical_button')), findsOneWidget);
      expect(find.byKey(const Key('split_horizontal_button')), findsOneWidget);

      // Tap vertical split
      await tester.tap(find.byKey(const Key('split_vertical_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap horizontal split
      await tester.tap(find.byKey(const Key('split_horizontal_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Top tab bar should only have 1 tab header (the root tab)
      expect(find.byKey(const Key('tab_header_local_shell'), skipOffstage: false), findsNothing);
      expect(find.byIcon(LucideIcons.columns2), findsOneWidget);
      expect(find.byIcon(LucideIcons.rows2), findsOneWidget);
    });

    testWidgets('⌘+click selects panes for broadcast; plain click clears it', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Open one local shell, then split twice -> three panes (headers appear).
      await tester.tap(find.byKey(const Key('empty_open_local_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const Key('split_vertical_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const Key('split_horizontal_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(TerminalView), findsNWidgets(3));

      // ⌘+click pane 0 and pane 1 -> two panes selected, broadcast live.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.tap(find.byType(TerminalView).at(0));
      await tester.pump();
      await tester.tap(find.byType(TerminalView).at(1));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(find.textContaining('· broadcast'), findsNWidgets(2));
      // Status bar reports deliverable/selected. flutter_pty's native library
      // is not loadable under `flutter test`, so no pane has a live session
      // here and nothing is deliverable — the counter has to say so rather
      // than count panes that would silently swallow the input.
      expect(find.text('broadcast 0/2'), findsOneWidget);

      // Plain click on an unselected pane exits broadcast.
      await tester.tap(find.byType(TerminalView).at(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('broadcast'), findsNothing);
    });
  });
}
