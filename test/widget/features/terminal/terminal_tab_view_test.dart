import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/bookmarks/presentation/notifiers/bookmarks_notifier.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/hosts/presentation/notifiers/hosts_notifier.dart';
import 'package:shellvibe/features/templates/data/repositories/templates_repository.dart';
import 'package:shellvibe/features/templates/domain/models/template_model.dart';
import 'package:shellvibe/features/templates/domain/models/template_pane_model.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:shellvibe/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:shellvibe/features/terminal/presentation/views/terminal_tab_view.dart';
import 'package:shellvibe/features/terminal/presentation/widgets/resizable_split.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:xterm3/xterm.dart';
import 'package:shellvibe/core/network/local_pty_manager.dart';
import 'package:shellvibe/core/network/providers/network_providers.dart';

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
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
      ],
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

      expect(find.text('No open sessions'), findsOneWidget);
      expect(find.byKey(const Key('empty_open_local_button')), findsOneWidget);
      expect(find.byKey(const Key('empty_select_host_button')), findsOneWidget);
    });

    testWidgets('Does not expose or trigger a local shell on mobile', (
      tester,
    ) async {
      debugPlatformCapabilitiesOverride = TargetPlatform.android;
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        ],
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
        find.text(
          'Connect to a saved server, or take over a session from your '
          'desktop.',
        ),
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
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
          ],
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
        // real attach path also reaches the tab strip.
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
          find.byTooltip('Device Link · ${shared.title} — click to disconnect'),
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

    testWidgets(
      'Vertical and Horizontal split buttons create split sessions without extra top tab bar entries',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Open initial local tab
        await tester.tap(find.byKey(const Key('empty_open_local_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byKey(const Key('split_vertical_button')), findsOneWidget);
        expect(
          find.byKey(const Key('split_horizontal_button')),
          findsOneWidget,
        );

        // Tap vertical split
        await tester.tap(find.byKey(const Key('split_vertical_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Tap horizontal split
        await tester.tap(find.byKey(const Key('split_horizontal_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Top tab bar should only have 1 tab header (the root tab)
        expect(
          find.byKey(const Key('tab_header_local_shell'), skipOffstage: false),
          findsNothing,
        );
        expect(find.byIcon(LucideIcons.columns2), findsOneWidget);
        expect(find.byIcon(LucideIcons.rows2), findsOneWidget);
      },
    );

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

      expect(find.textContaining('· BROADCAST'), findsNWidgets(2));
      // Each selected pane's header reports deliverable/selected.
      // flutter_pty's native library is not loadable under `flutter test`, so
      // no pane has a live session here and nothing is deliverable — the
      // counter has to say so rather than count panes that would silently
      // swallow the input.
      expect(find.textContaining('· BROADCAST 0/2'), findsNWidgets(2));

      // Plain click on an unselected pane exits broadcast.
      await tester.tap(find.byType(TerminalView).at(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('BROADCAST'), findsNothing);
    });

    testWidgets('right-clicking a terminal opens the pane menu', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        ],
      );
      final notifier = container.read(terminalTabsProvider.notifier);
      notifier.openLocalTab(title: 'A');
      final first = container.read(terminalTabsProvider).activeTabId!;

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

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey(first))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('terminal_menu_copy')), findsOneWidget);
      expect(find.byKey(const Key('terminal_menu_paste')), findsOneWidget);
      expect(find.byKey(const Key('terminal_menu_select_all')), findsOneWidget);
      expect(find.byKey(const Key('terminal_menu_find')), findsOneWidget);
      expect(find.byKey(const Key('terminal_menu_clear')), findsOneWidget);
      expect(find.byKey(const Key('terminal_menu_broadcast')), findsOneWidget);
      // Snippets live here (and on ⌘⇧S) rather than in a strip pinned under
      // the panes, so they cost no terminal rows when nobody is sending one.
      expect(find.byKey(const Key('terminal_menu_snippets')), findsOneWidget);
      expect(find.byKey(const Key('terminal_snippet_drawer')), findsNothing);
      // The tab bar's own actions are repeated here, aimed at this pane.
      expect(
        find.byKey(const Key('terminal_menu_split_vertical')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('terminal_menu_close_tab')), findsOneWidget);
      // One pane: closing it is closing the tab, so only one of the two rows
      // is offered.
      expect(find.byKey(const Key('terminal_menu_close_pane')), findsNothing);
      // Nothing is selected, so Copy is shown but cannot be chosen.
      final copyItem = tester.widget<PopupMenuItem<VoidCallback>>(
        find.byKey(const Key('terminal_menu_copy')),
      );
      expect(copyItem.enabled, isFalse);
      // A local shell has no remote side to transfer files to.
      expect(find.byKey(const Key('terminal_menu_sftp')), findsNothing);

      await tester.tap(find.byKey(const Key('terminal_menu_split_vertical')));
      await tester.pumpAndSettle();

      // The menu row split the pane it was opened on.
      expect(container.read(terminalTabsProvider).tabs.length, equals(2));

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pumpAndSettle();
    });

    testWidgets('pasting multi-line clipboard text asks before running it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var clipboard = 'echo one\necho two\n';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        ],
      );
      final notifier = container.read(terminalTabsProvider.notifier);
      notifier.openLocalTab(title: 'A');
      final first = container.read(terminalTabsProvider).activeTabId!;

      // The pane has no shell behind it here, so the terminal's output slot
      // stands in for the PTY that would normally receive the paste.
      final written = <String>[];
      container.read(terminalTabsProvider).tabs.single.terminal.onOutput =
          written.add;

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

      Future<void> openMenu() async {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(ValueKey(first))),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await openMenu();
      await tester.tap(find.byKey(const Key('terminal_menu_paste')));
      await tester.pumpAndSettle();

      expect(find.text('Paste and run?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('unsafe_paste_cancel_button')));
      await tester.pumpAndSettle();
      expect(written, isEmpty);

      // A single line cannot run on its own, so it goes straight through.
      clipboard = 'echo one';
      await openMenu();
      await tester.tap(find.byKey(const Key('terminal_menu_paste')));
      await tester.pumpAndSettle();

      expect(find.text('Paste and run?'), findsNothing);
      expect(written.join(), contains('echo one'));

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pumpAndSettle();
    });

    testWidgets('a split tab offers Close Pane in the menu', (tester) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        ],
      );
      final notifier = container.read(terminalTabsProvider.notifier);
      notifier.openLocalTab(title: 'A');
      final first = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(first, direction: Axis.horizontal);

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

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey(first))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('terminal_menu_close_pane')), findsOneWidget);

      await tester.tap(find.byKey(const Key('terminal_menu_close_pane')));
      await tester.pumpAndSettle();

      final state = container.read(terminalTabsProvider);
      expect(state.tabs.length, equals(1));
      expect(state.tabs.single.id, isNot(equals(first)));

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pumpAndSettle();
    });

    testWidgets('the Connect to Host panel puts favorites first', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        ],
      );
      addTearDown(container.dispose);

      final hosts = container.read(hostsProvider.notifier);
      final alpha = await hosts.addHost(
        workspaceId: 'default',
        label: 'Alpha',
        hostname: 'alpha.internal',
      );
      final zulu = await hosts.addHost(
        workspaceId: 'default',
        label: 'Zulu',
        hostname: 'zulu.internal',
      );
      await container.read(bookmarksProvider.future);
      // The one that sorts last is the one that is starred, so leading the
      // list cannot be an accident of the host order.
      await container.read(bookmarksProvider.notifier).toggleHost(zulu.id);

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
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('empty_select_host_button')));
      await tester.pumpAndSettle();

      // Scoped to the panel's own list: the empty screen behind the modal
      // carries a FAVORITES heading of its own over the shortcut chips.
      Finder heading(String text) =>
          find.descendant(of: find.byType(ListView), matching: find.text(text));
      // ShellVibeSectionLabel renders its heading uppercased.
      expect(heading('FAVORITES'), findsOneWidget);
      expect(heading('ALL HOSTS'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(Key('select_host_row_${zulu.id}'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(Key('select_host_row_${alpha.id}'))).dy,
        ),
      );
      // Each host is listed once: a favorite is not repeated below.
      expect(find.byKey(Key('select_host_row_${zulu.id}')), findsOneWidget);

      // A search that matches only the unstarred host drops the heading with
      // it, so the panel never shows an empty section.
      await tester.enterText(
        find.byKey(const Key('select_host_search_input')),
        'alpha',
      );
      await tester.pumpAndSettle();
      expect(heading('FAVORITES'), findsNothing);
      expect(find.byKey(Key('select_host_row_${alpha.id}')), findsOneWidget);
    });

    testWidgets('the Connect to Host panel filters its list as you type', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        ],
      );
      addTearDown(container.dispose);

      final hosts = container.read(hostsProvider.notifier);
      await hosts.addHost(
        workspaceId: 'default',
        label: 'Production web',
        hostname: '10.0.0.5',
        username: 'deploy',
      );
      await hosts.addHost(
        workspaceId: 'default',
        label: 'Staging web',
        hostname: 'staging.internal',
        username: 'deploy',
      );
      await hosts.addHost(
        workspaceId: 'default',
        label: 'Database',
        hostname: 'db.internal',
        username: 'postgres',
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
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('empty_select_host_button')));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNWidgets(3));

      // Matches the hostname, not the label, so the search has to look past
      // the name the row leads with.
      await tester.enterText(
        find.byKey(const Key('select_host_search_input')),
        'db.',
      );
      await tester.pumpAndSettle();

      expect(find.text('Database'), findsOneWidget);
      expect(find.text('Production web'), findsNothing);
      expect(find.text('Staging web'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('select_host_search_input')),
        'deploy',
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(2));

      await tester.enterText(
        find.byKey(const Key('select_host_search_input')),
        'nothing here',
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('No hosts match that search.'), findsOneWidget);
    });

    testWidgets('the Connect to Host panel lists and runs templates', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        ],
      );

      await container
          .read(hostsProvider.notifier)
          .addHost(
            workspaceId: 'default',
            label: 'Database',
            hostname: 'db.internal',
          );
      await TemplatesRepository(db.templatesDao).addTemplate(
        TemplateModel(
          id: 'tpl-1',
          workspaceId: 'default',
          name: 'Morning shells',
          panes: const [
            TemplatePaneModel(
              id: 'p0',
              templateId: 'tpl-1',
              paneOrder: 0,
              sessionType: TerminalSessionType.local,
              title: 'build',
            ),
            TemplatePaneModel(
              id: 'p1',
              templateId: 'tpl-1',
              paneOrder: 1,
              sessionType: TerminalSessionType.local,
              title: 'logs',
            ),
          ],
          createdAt: DateTime(2026),
        ),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.dark(),
              brightness: Brightness.dark,
            ),
            child: const MaterialApp(
              // Running a template reports its outcome in a toast.
              home: ShadToaster(child: TerminalTabView()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('empty_select_host_button')));
      await tester.pumpAndSettle();

      final row = find.byKey(const Key('select_template_row_tpl-1'));
      expect(row, findsOneWidget);
      expect(find.text('2 tabs'), findsOneWidget);

      // The search covers templates too.
      await tester.enterText(
        find.byKey(const Key('select_host_search_input')),
        'morning',
      );
      await tester.pumpAndSettle();
      expect(find.text('Database'), findsNothing);
      expect(row, findsOneWidget);

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(
        [
          for (final tab in container.read(terminalTabsProvider).tabs)
            tab.title,
        ],
        ['build', 'logs'],
      );

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pumpAndSettle();
    });

    testWidgets('dragging a pane header onto another pane swaps them', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        ],
      );
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'A');
      final first = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(first, direction: Axis.horizontal);
      final second = container.read(terminalTabsProvider).tabs.last.id;
      // A ratio the dock path would not produce, so this asserts a swap and
      // not merely a rearrangement that happens to look like one.
      notifier.setSplitRatio(second, 0.3);

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

      final handle = find.byWidgetPredicate(
        (widget) => widget is Draggable<String> && widget.data == second,
      );
      expect(handle, findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      // The middle of the other pane, well inside the region that swaps rather
      // than docking.
      await gesture.moveTo(tester.getCenter(find.byKey(ValueKey(first))));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final state = container.read(terminalTabsProvider);
      final movedUp = state.tabs.firstWhere((t) => t.id == second);
      final movedDown = state.tabs.firstWhere((t) => t.id == first);
      expect(movedUp.splitParentId, isNull);
      expect(movedDown.splitParentId, equals(second));
      expect(movedDown.splitDirection, equals(Axis.horizontal));
      expect(movedDown.splitRatio, equals(0.3));
      // Neither terminal was rebuilt away by the swap.
      expect(find.byType(TerminalView), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pumpAndSettle();
    });

    testWidgets('dropping a pane on the edge of another docks it there', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        ],
      );
      final notifier = container.read(terminalTabsProvider.notifier);

      notifier.openLocalTab(title: 'A');
      final first = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(first, direction: Axis.horizontal);
      final second = container.read(terminalTabsProvider).tabs.last.id;

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

      final handle = find.byWidgetPredicate(
        (widget) => widget is Draggable<String> && widget.data == second,
      );
      final targetRect = tester.getRect(find.byKey(ValueKey(first)));

      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await gesture.moveTo(Offset(targetRect.center.dx, targetRect.bottom - 8));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Side by side became stacked: the dragged pane now splits the other
      // one's rectangle along the edge it was dropped on.
      final state = container.read(terminalTabsProvider);
      final docked = state.tabs.firstWhere((t) => t.id == second);
      expect(docked.splitParentId, equals(first));
      expect(docked.splitDirection, equals(Axis.vertical));
      expect(find.byType(TerminalView), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pumpAndSettle();
    });

    testWidgets('a split cuts only the pane it was taken from', (tester) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        ],
      );
      final notifier = container.read(terminalTabsProvider.notifier);

      // Three side-by-side panes, then a stacked split taken from the first
      // one — the case where folding splits in creation order used to lay the
      // new pane out under the whole row.
      notifier.openLocalTab(title: 'A');
      final first = container.read(terminalTabsProvider).activeTabId!;
      notifier.splitTab(first, direction: Axis.horizontal);
      final second = container.read(terminalTabsProvider).tabs.last.id;
      notifier.splitTab(second, direction: Axis.horizontal);
      final third = container.read(terminalTabsProvider).tabs.last.id;
      notifier.splitTab(third, direction: Axis.vertical);
      notifier.splitTab(first, direction: Axis.vertical);

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

      expect(find.byType(TerminalView), findsNWidgets(5));

      final stacked = find.byWidgetPredicate(
        (widget) => widget is ResizableSplit && widget.axis == Axis.vertical,
      );
      expect(stacked, findsNWidgets(2));
      // Each stacked split holds its own pane plus the one split off it, and
      // nothing else: two panes, never the whole row.
      for (var i = 0; i < 2; i++) {
        expect(
          find.descendant(
            of: stacked.at(i),
            matching: find.byType(TerminalView),
          ),
          findsNWidgets(2),
        );
      }

      // The container outlives the widget tree here, so it is disposed inside
      // the test body: the tab notifier owns the pane sessions and only
      // releases their timers when it goes.
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pumpAndSettle();
    });
  });

  group('AI tabs', () {
    testWidgets('an agent session is badged and takes no keyboard input', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        ],
      );

      final tabId = container
          .read(terminalTabsProvider.notifier)
          .openMcpTab(
            mcpSessionId: 'mcp-1',
            title: 'prod-web-01',
            onClose: () {},
          );
      container.read(terminalTabsProvider.notifier).setActiveTab(tabId);

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

      // The badge is how the user tells, across a row of tabs, which shell
      // something other than them is driving.
      expect(find.text('AI'), findsOneWidget);

      final terminalView = tester.widget<TerminalView>(
        find.byType(TerminalView),
      );
      expect(terminalView.readOnly, isTrue);

      // Same as the Device Link case above: the keep-alive tab notifier owns
      // the session's terminal, so the container has to be disposed inside
      // the test body or its timers outlive the tree.
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pumpAndSettle();
    });

    testWidgets('a host tab names its endpoint on the tab and pane headers', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        ],
      );
      HostModel host(String id, String hostname, int port) => HostModel(
        id: id,
        workspaceId: 'ws',
        label: id,
        hostname: hostname,
        username: 'deploy',
        port: port,
        createdAt: DateTime(2026),
      );
      final notifier = container.read(terminalTabsProvider.notifier);
      final root = TerminalTabSession(
        id: 'root',
        title: 'web-01',
        sessionType: TerminalSessionType.ssh,
        host: host('web-01', '10.0.0.5', 2222),
        terminal: Terminal(maxLines: 100),
      );
      notifier.registerDeviceLinkSession(root);

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

      // One pane: no header to carry it, so the tab does.
      expect(find.byTooltip('deploy@10.0.0.5:2222'), findsOneWidget);
      expect(find.byKey(const Key('pane_endpoint_root')), findsNothing);

      notifier.registerDeviceLinkSession(
        TerminalTabSession(
          id: 'pane',
          title: 'db-01',
          sessionType: TerminalSessionType.ssh,
          host: host('db-01', 'db.internal', 22),
          terminal: Terminal(maxLines: 100),
          splitParentId: 'root',
          splitDirection: Axis.horizontal,
        ),
      );
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('pane_endpoint_root'))).data,
        'deploy@10.0.0.5:2222',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('pane_endpoint_pane'))).data,
        'deploy@db.internal:22',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pumpAndSettle();
    });

    testWidgets('dragging a tab along the strip reorders it; a click selects', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        ],
      );
      final notifier = container.read(terminalTabsProvider.notifier);
      notifier.openLocalTab(title: 'one');
      notifier.openLocalTab(title: 'two');
      notifier.openLocalTab(title: 'three');
      final ids = [
        for (final tab in container.read(terminalTabsProvider).tabs) tab.id,
      ];

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

      final first = find.byKey(Key('tab_header_${ids[0]}'));
      final last = find.byKey(Key('tab_header_${ids[2]}'));
      final start = tester.getCenter(first);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 50));
      // In steps, as a hand would: the list re-measures its gaps as the tab
      // passes each neighbour.
      final distance = tester.getTopRight(last).dx + 10 - start.dx;
      for (var step = 0; step < 10; step++) {
        await gesture.moveBy(Offset(distance / 10, 0));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        [for (final tab in container.read(terminalTabsProvider).tabs) tab.id],
        [ids[1], ids[2], ids[0]],
      );

      // The drag listener does not swallow a plain click.
      await tester.tap(find.byKey(Key('tab_header_${ids[1]}')));
      await tester.pump();
      expect(container.read(terminalTabsProvider).activeTabId, ids[1]);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pumpAndSettle();
    });

    testWidgets('right-clicking a tab offers to close the tabs around it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        ],
      );
      final notifier = container.read(terminalTabsProvider.notifier);
      for (final title in ['one', 'two', 'three']) {
        notifier.openLocalTab(title: title);
      }
      final ids = [
        for (final tab in container.read(terminalTabsProvider).tabs) tab.id,
      ];

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

      Future<void> rightClick(String id) async {
        await tester.tap(
          find.byKey(Key('tab_header_$id')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
      }

      await rightClick(ids[0]);
      expect(find.byKey(const Key('tab_menu_close_others')), findsOneWidget);
      expect(find.byKey(const Key('tab_menu_close_left')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tab_menu_close_right')));
      await tester.pumpAndSettle();

      expect(
        [for (final tab in container.read(terminalTabsProvider).tabs) tab.id],
        [ids[0]],
      );

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pumpAndSettle();
    });

    testWidgets('closing the tab ends the agent session', (tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
        ],
      );
      var sessionClosed = false;

      final tabId = container
          .read(terminalTabsProvider.notifier)
          .openMcpTab(
            mcpSessionId: 'mcp-1',
            title: 'prod-web-01',
            onClose: () => sessionClosed = true,
          );
      container.read(terminalTabsProvider.notifier).setActiveTab(tabId);

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

      await tester.tap(find.byKey(Key('close_tab_$tabId')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(sessionClosed, isTrue);

      // Same as the Device Link case above: the keep-alive tab notifier owns
      // the session's terminal, so the container has to be disposed inside
      // the test body or its timers outlive the tree.
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pumpAndSettle();
    });
  });
}

/// Widget tests must not start real shells.
///
/// A local pane now attaches on its own isolate, so leaving the real manager
/// in place would have every one of these tests spawn one and wait on a
/// process that cannot exist in a test binary.
class _NoShellPtyManager extends LocalPtyManager {
  @override
  Future<TerminalLocalPtyBridge?> startAndBridge(
    Terminal terminal, {
    String? executable,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 24,
    int columns = 80,
    void Function(Uint8List bytes)? outputTap,
  }) async => null;
}
