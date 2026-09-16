import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/features/snippets/domain/models/snippet_model.dart';
import 'package:shellvibe/features/snippets/presentation/widgets/snippet_picker_sheet.dart';
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

  tearDown(() async => db.close());

  Future<void> seed(String id, String title, String code) =>
      db.snippetsDao.insertSnippet(
        SnippetsCompanion.insert(
          id: id,
          workspaceId: 'default',
          title: title,
          code: code,
        ),
      );

  Future<void> pump(
    WidgetTester tester, {
    required void Function(SnippetModel) onSelect,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: MaterialApp(
            home: Scaffold(
              body: SnippetPickerSheet(
                targetLabel: 'Send to the active pane',
                onSelect: (snippet) async => onSelect(snippet),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('names its target and lists every snippet', (tester) async {
    await seed('s1', 'Disk usage', 'df -h');
    await seed('s2', 'Uptime', 'uptime');

    await pump(tester, onSelect: (_) {});

    expect(find.text('SEND TO THE ACTIVE PANE'), findsOneWidget);
    expect(find.byKey(const Key('snippet_picker_s1')), findsOneWidget);
    expect(find.byKey(const Key('snippet_picker_s2')), findsOneWidget);
  });

  testWidgets('filters as you type, over code as well as title', (
    tester,
  ) async {
    await seed('s1', 'Disk usage', 'df -h');
    await seed('s2', 'Uptime', 'uptime');

    await pump(tester, onSelect: (_) {});
    await tester.enterText(
      find.byKey(const Key('snippet_picker_search')),
      'df',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('snippet_picker_s1')), findsOneWidget);
    expect(find.byKey(const Key('snippet_picker_s2')), findsNothing);
  });

  testWidgets('hands the picked snippet back', (tester) async {
    await seed('s1', 'Disk usage', 'df -h');
    SnippetModel? picked;

    await pump(tester, onSelect: (snippet) => picked = snippet);
    await tester.tap(find.byKey(const Key('snippet_picker_s1')));
    await tester.pumpAndSettle();

    expect(picked?.id, 's1');
  });

  testWidgets('points at the library when there is nothing to send', (
    tester,
  ) async {
    await pump(tester, onSelect: (_) {});

    expect(find.textContaining('No snippets yet.'), findsOneWidget);
  });
}
