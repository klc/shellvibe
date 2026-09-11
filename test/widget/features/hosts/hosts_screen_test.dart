import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
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
