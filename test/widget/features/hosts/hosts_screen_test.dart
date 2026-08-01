import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:terly2/features/hosts/domain/models/host_model.dart';
import 'package:terly2/features/hosts/presentation/screens/hosts_screen.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/providers/database_providers.dart';

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
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        home: HostsScreen(onConnectHost: onConnectHost),
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

    testWidgets('Renders host tile when host exists in database and triggers onConnectHost on tap', (tester) async {
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
    });

    testWidgets('Opens HostGroupFormDialog when add_group_button is tapped', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('add_group_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Add Folder / Group'), findsOneWidget);
      expect(find.byKey(const Key('group_name_input')), findsOneWidget);
    });

    testWidgets('Opens HostFormDialog and displays username field', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('add_host_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Add Server Host'), findsOneWidget);
      expect(find.byKey(const Key('host_label_input')), findsOneWidget);
      expect(find.byKey(const Key('host_hostname_input')), findsOneWidget);
      expect(find.byKey(const Key('host_username_input')), findsOneWidget);
    });
  });
}
