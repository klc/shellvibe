import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/hosts/presentation/screens/hosts_screen.dart';
import 'package:shellvibe/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'default',
        name: 'Default Workspace',
        createdAt: DateTime.now(),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Widget createWidgetUnderTest({void Function(HostModel host)? onConnectHost}) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.light(),
          brightness: Brightness.light,
        ),
        child: MaterialApp(
          builder: (context, child) => Material(child: child!),
          home: HostsScreen(onConnectHost: onConnectHost),
        ),
      ),
    );
  }

  Future<void> seedHost(String id, String label, String hostname) {
    return db.hostsDao.insertHost(
      HostsCompanion.insert(
        id: id,
        workspaceId: 'default',
        label: label,
        hostname: hostname,
        createdAt: DateTime.now(),
      ),
    );
  }

  group('Host favorites', () {
    testWidgets('the star appears on hover and filters the list', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedHost('host-1', 'Production', '10.0.0.5');
      await seedHost('host-2', 'Staging', '10.0.0.6');

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Nothing starred and no pointer over a row: the list looks as it did.
      expect(find.byKey(const Key('favorite_host_host-1')), findsNothing);

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.text('Production'))),
      );
      await tester.pumpAndSettle();

      final star = find.byKey(const Key('favorite_host_host-1'));
      expect(star, findsOneWidget);
      await tester.tap(star);
      await tester.pumpAndSettle();

      // Starred rows keep their star once the pointer leaves.
      await tester.sendEventToBinding(pointer.hover(const Offset(5, 5)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('favorite_host_host-1')), findsOneWidget);
      expect(find.byKey(const Key('favorite_host_host-2')), findsNothing);

      // The filter shows the starred host and only that one. The list itself
      // was never reordered.
      await tester.tap(find.byKey(const Key('hosts_filter_favorites')));
      await tester.pumpAndSettle();
      expect(find.text('Production'), findsOneWidget);
      expect(find.text('Staging'), findsNothing);
    });
  });

  group('HostsScreen Widget Tests', () {
    testWidgets('Renders AppBar title and action buttons', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Hosts & Servers'), findsOneWidget);
      expect(find.byKey(const Key('add_group_button')), findsOneWidget);
      expect(find.byKey(const Key('add_host_button')), findsOneWidget);
      expect(find.byKey(const Key('hosts_search_input')), findsOneWidget);
    });

    testWidgets('Renders empty state when no hosts exist', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('No hosts or groups configured.'), findsOneWidget);
    });

    testWidgets('Renders an empty group so it can still be managed', (
      tester,
    ) async {
      await db.hostsDao.insertHostGroup(
        HostGroupsCompanion.insert(
          id: 'empty-group',
          workspaceId: 'default',
          name: 'Empty Group',
        ),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Empty Group'), findsOneWidget);
      expect(find.byKey(const ValueKey('group_empty-group')), findsOneWidget);
      expect(find.text('No hosts or groups configured.'), findsNothing);
    });

    testWidgets(
      'Renders host tile when host exists in database and triggers onConnectHost on tap',
      (tester) async {
        // Pre-insert a host into database
        await db.hostsDao.insertHost(
          HostsCompanion.insert(
            id: 'host-1',
            workspaceId: 'default',
            label: 'Production Server',
            hostname: '192.168.1.100',
            username: const Value('ubuntu'),
            port: const Value(22),
            createdAt: DateTime.now(),
          ),
        );

        HostModel? connectedHost;

        await tester.pumpWidget(
          createWidgetUnderTest(
            onConnectHost: (host) {
              connectedHost = host;
            },
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Host list rendered
        expect(find.text('Production Server'), findsOneWidget);
        expect(find.text('ubuntu@192.168.1.100:22'), findsOneWidget);

        // Tap connect icon button
        final connectButton = find.byKey(const Key('connect_host_host-1'));
        expect(connectButton, findsOneWidget);

        await tester.tap(connectButton);
        await tester.pump();

        expect(connectedHost, isNotNull);
        expect(connectedHost!.id, equals('host-1'));
        expect(connectedHost!.label, equals('Production Server'));
      },
    );

    testWidgets('Filters hosts by the visible username', (tester) async {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'host-username-match',
          workspaceId: 'default',
          label: 'Production Server',
          hostname: '192.168.1.100',
          username: const Value('ubuntu'),
          createdAt: DateTime.now(),
        ),
      );
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'host-username-miss',
          workspaceId: 'default',
          label: 'Database Server',
          hostname: '192.168.1.101',
          username: const Value('postgres'),
          createdAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(
        find.byKey(const Key('hosts_search_input')),
        'ubuntu',
      );
      await tester.pump();

      expect(find.text('Production Server'), findsOneWidget);
      expect(find.text('Database Server'), findsNothing);
    });

    testWidgets('Scopes the flat host list to the selected group filter', (
      tester,
    ) async {
      await db.hostsDao.insertHostGroup(
        HostGroupsCompanion.insert(
          id: 'group-a',
          workspaceId: 'default',
          name: 'Group A',
        ),
      );
      await db.hostsDao.insertHostGroup(
        HostGroupsCompanion.insert(
          id: 'group-b',
          workspaceId: 'default',
          name: 'Group B',
        ),
      );
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'host-a',
          workspaceId: 'default',
          groupId: const Value('group-a'),
          label: 'Alpha Server',
          hostname: 'alpha.example.com',
          createdAt: DateTime.now(),
        ),
      );
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'host-b',
          workspaceId: 'default',
          groupId: const Value('group-b'),
          label: 'Beta Server',
          hostname: 'beta.example.com',
          createdAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // Groups are filters in the context column / chip bar, not expandable
      // sections: selecting one scopes the single flat list.
      await tester.tap(find.byKey(const Key('group_group-a')));
      await tester.pumpAndSettle();
      expect(find.text('Alpha Server'), findsOneWidget);
      expect(find.text('Beta Server'), findsNothing);

      await tester.tap(find.byKey(const Key('group_group-b')));
      await tester.pumpAndSettle();
      expect(find.text('Beta Server'), findsOneWidget);
      expect(find.text('Alpha Server'), findsNothing);

      // A search inside a scoped group narrows further rather than escaping it.
      await tester.enterText(
        find.byKey(const Key('hosts_search_input')),
        'alpha',
      );
      await tester.pumpAndSettle();
      expect(find.text('Beta Server'), findsNothing);
      expect(find.text('Alpha Server'), findsNothing);
      expect(find.text('No hosts match your search.'), findsOneWidget);
    });

    testWidgets('Host row reads its address in full at a phone width', (
      tester,
    ) async {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'host-addr',
          workspaceId: 'default',
          label: 'Oracle Ubuntu',
          hostname: '152.70.22.207',
          username: const Value('ubuntu'),
          port: const Value(22),
          createdAt: DateTime.now(),
        ),
      );

      tester.view.physicalSize = const Size(411, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final name = find.text('Oracle Ubuntu');
      final addressText = find.text('ubuntu@152.70.22.207:22');

      // Beside the name column the address had about 123px of a 411px row and
      // wanted 160, so it ellipsised mid-IP: "ubuntu@152.70.2…". Stacked under
      // the name it starts at the same x, one line lower, with the row's whole
      // width to itself. (Asserted as geometry rather than as
      // `didExceedMaxLines`, which under the test font measures a width no
      // real device renders.)
      expect(
        tester.getTopLeft(addressText).dy,
        greaterThan(tester.getTopLeft(name).dy),
      );
      expect(
        tester.getTopLeft(addressText).dx,
        equals(tester.getTopLeft(name).dx),
      );
      expect(tester.getSize(addressText).width, greaterThan(200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Save and connect" connects the host it just saved', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      // The dialog and the prompt after it both need room to be tapped.
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(home: HostsScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('add_host_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(
        find.byKey(const Key('host_label_input')),
        'Oracle Ubuntu',
      );
      // Unroutable on purpose: the connect this test is about opens a real
      // socket, and a test has no business reaching a real server.
      await tester.enterText(
        find.byKey(const Key('host_hostname_input')),
        '192.168.1.99',
      );
      await tester.enterText(
        find.byKey(const Key('host_username_input')),
        'ubuntu',
      );
      await tester.tap(find.byKey(const Key('host_save_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The button says "Save and connect". It used to only save: the dialog
      // popped its result into a caller that never looked at it.
      expect(find.byKey(const Key('connect_password_input')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('connect_password_input')),
        'hunter2',
      );
      await tester.tap(
        find.byKey(const Key('connect_credentials_submit_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final tabs = container.read(terminalTabsProvider).tabs;
      expect(tabs.length, equals(1));
      expect(tabs.first.title, equals('Oracle Ubuntu'));

      // Drains the connect attempt's timeout so it does not outlive the test.
      await container
          .read(terminalTabsProvider.notifier)
          .closeTab(tabs.first.id);
      await tester.pump(const Duration(seconds: 16));
    });

    testWidgets('Cancelling the credential prompt opens no session', (
      tester,
    ) async {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'host-cancel',
          workspaceId: 'default',
          label: 'No Identity Host',
          hostname: '192.168.1.50',
          username: const Value('root'),
          createdAt: DateTime.now(),
        ),
      );

      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(home: HostsScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('connect_host_host-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(
        find.byKey(const Key('connect_credentials_cancel_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Calling the prompt off calls the connection off: no half-open tab
      // left behind to report an authentication failure.
      expect(container.read(terminalTabsProvider).tabs, isEmpty);
    });

    testWidgets('Host row and its action menu fit a phone width', (
      tester,
    ) async {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'host-phone',
          workspaceId: 'default',
          label: 'contabo',
          hostname: '173.249.100.100',
          username: const Value('root'),
          createdAt: DateTime.now(),
        ),
      );

      tester.view.physicalSize = const Size(411, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'row layout');

      // The popup menu is laid out separately from the row; pinning the
      // button's `constraints` used to squeeze the menu itself.
      await tester.tap(find.byIcon(LucideIcons.ellipsis));
      await tester.pumpAndSettle();

      expect(find.text('Edit host'), findsOneWidget);
      expect(find.text('Delete host'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'action menu layout');
    });

    testWidgets('Selecting a host on a phone width does not overflow the row', (
      tester,
    ) async {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'host-phone',
          workspaceId: 'default',
          label: 'contabo',
          hostname: '173.249.100.100',
          username: const Value('root'),
          createdAt: DateTime.now(),
        ),
      );

      tester.view.physicalSize = const Size(411, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The selected row used to swap its icon action for the spelled-out
      // Open pill, which pushed the overflow menu past the screen edge.
      await tester.tap(find.text('contabo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull, reason: 'selected row layout');
      expect(find.byKey(const Key('connect_host_host-phone')), findsWidgets);
    });

    testWidgets('Opens HostGroupFormDialog when add_group_button is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('add_group_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Add Folder / Group'), findsOneWidget);
      expect(find.byKey(const Key('group_name_input')), findsOneWidget);
    });

    testWidgets('Opens HostFormDialog and displays username field', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('add_host_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('New host'), findsOneWidget);
      expect(find.byKey(const Key('host_label_input')), findsOneWidget);
      expect(find.byKey(const Key('host_hostname_input')), findsOneWidget);
      expect(find.byKey(const Key('host_username_input')), findsOneWidget);
    });

    testWidgets(
      'Triggers defaultConnectHost opening tab when onConnectHost is null',
      (tester) async {
        await db.hostsDao.insertHost(
          HostsCompanion.insert(
            id: 'host-2',
            workspaceId: 'default',
            label: 'Default Host Test',
            hostname: '192.168.1.101',
            username: const Value('root'),
            port: const Value(22),
            createdAt: DateTime.now(),
          ),
        );

        final container = ProviderContainer(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: ShadTheme(
              data: ShadThemeData(
                colorScheme: const ShadSlateColorScheme.light(),
                brightness: Brightness.light,
              ),
              child: const MaterialApp(home: HostsScreen()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final connectButton = find.byKey(const Key('connect_host_host-2'));
        expect(connectButton, findsOneWidget);

        await tester.tap(connectButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // This host is bound to no identity, which the form calls
        // "(None - Prompt on Connect)": it is asked for credentials rather
        // than walked straight into "all authentication methods failed".
        expect(find.byKey(const Key('connect_password_input')), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('connect_password_input')),
          'hunter2',
        );
        await tester.tap(
          find.byKey(const Key('connect_credentials_submit_button')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final tabsState = container.read(terminalTabsProvider);
        expect(tabsState.tabs.length, equals(1));
        expect(tabsState.tabs.first.title, equals('Default Host Test'));

        await container
            .read(terminalTabsProvider.notifier)
            .closeTab(tabsState.tabs.first.id);
        await tester.pump(const Duration(seconds: 16));
      },
    );
  });
}
