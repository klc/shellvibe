import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Widget createWidgetUnderTest() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: const MaterialApp(
        home: HostsScreen(),
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

    testWidgets('Opens HostFormDialog when add_host_button is tapped', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('add_host_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Add Server Host'), findsOneWidget);
      expect(find.byKey(const Key('host_label_input')), findsOneWidget);
      expect(find.byKey(const Key('host_hostname_input')), findsOneWidget);
    });
  });
}
