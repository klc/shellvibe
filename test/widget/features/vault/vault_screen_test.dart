import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:terly2/features/vault/presentation/screens/vault_screen.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
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
        home: VaultScreen(),
      ),
    );
  }

  group('VaultScreen Widget Tests', () {
    testWidgets('Renders AppBar title and add button', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Identity Vault'), findsOneWidget);
      expect(find.byKey(const Key('add_identity_button')), findsOneWidget);
      expect(find.byKey(const Key('vault_search_input')), findsOneWidget);
    });

    testWidgets('Opens IdentityFormDialog on add button tap', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('add_identity_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Add New Identity'), findsOneWidget);
      expect(find.byKey(const Key('identity_title_input')), findsOneWidget);
      expect(find.byKey(const Key('identity_username_input')), findsOneWidget);
      expect(find.byKey(const Key('identity_save_button')), findsOneWidget);
    });
  });
}
