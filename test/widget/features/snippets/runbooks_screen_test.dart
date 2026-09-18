import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/features/snippets/presentation/screens/runbooks_screen.dart';
import 'package:shellvibe/features/snippets/presentation/screens/snippets_screen.dart';
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

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.light(),
          brightness: Brightness.light,
        ),
        child: MaterialApp(home: child),
      ),
    );
  }

  group('Runbooks section', () {
    testWidgets('Renders the empty state when no runbook exists', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const RunbooksScreen()));
      await tester.pumpAndSettle();

      expect(find.text('No runbooks defined.'), findsOneWidget);
      expect(find.text('Add Runbook'), findsOneWidget);
    });

    testWidgets('Automation library opens RunbookEditorDialog from the shell', (
      tester,
    ) async {
      // The header's add button only appears once the library is non-empty;
      // on an empty one the empty state owns that call to action.
      await db.runbooksDao.insertRunbook(
        RunbooksCompanion.insert(
          id: 'seed',
          workspaceId: 'default',
          title: 'Nightly checks',
          createdAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        wrap(
          const SnippetsScreen(
            initialSection: AutomationSection.runbooks,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_runbook_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('add_runbook_button')));
      await tester.pumpAndSettle();

      expect(find.text('New Runbook'), findsOneWidget);
      expect(find.byKey(const Key('runbook_title_field')), findsOneWidget);
      expect(find.byKey(const Key('runbook_add_step_button')), findsOneWidget);
    });
  });
}
