import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:terly2/features/snippets/presentation/screens/snippets_screen.dart';
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

  group('SnippetsScreen Widget Tests', () {
    testWidgets('Renders SnippetsScreen with title and search field', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
          ],
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: SnippetsScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Snippets Library'), findsOneWidget);
      expect(find.byKey(const Key('snippets_search_field')), findsOneWidget);
      expect(find.byKey(const Key('add_snippet_button')), findsOneWidget);
    });

    testWidgets('Opens SnippetFormDialog on add button tap', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
          ],
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: SnippetsScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add_snippet_button')));
      await tester.pumpAndSettle();

      expect(find.text('New Snippet'), findsOneWidget);
      expect(find.byKey(const Key('snippet_title_field')), findsOneWidget);
      expect(find.byKey(const Key('snippet_code_field')), findsOneWidget);
    });
  });
}

