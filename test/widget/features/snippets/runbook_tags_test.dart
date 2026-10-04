import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/features/snippets/data/repositories/runbooks_repository.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_model.dart';
import 'package:shellvibe/features/snippets/presentation/screens/snippets_screen.dart';
import 'package:shellvibe/features/snippets/presentation/widgets/runbook_editor_dialog.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    for (final (id, title, tags) in [
      ('a', 'Deploy API', '["ops","release"]'),
      ('b', 'Rotate logs', '["ops"]'),
      ('c', 'Warm caches', '["perf"]'),
      ('d', 'Untagged', null),
    ]) {
      await db.runbooksDao.insertRunbook(
        RunbooksCompanion.insert(
          id: id,
          workspaceId: 'default',
          title: title,
          createdAt: DateTime(2026),
          tags: Value(tags),
        ),
      );
    }
  });

  tearDown(() => db.close());

  Widget app(Widget child) => ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: ShadTheme(
      data: ShadThemeData(
        colorScheme: const ShadSlateColorScheme.light(),
        brightness: Brightness.light,
      ),
      child: MaterialApp(home: child),
    ),
  );

  Future<void> pumpLibrary(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(const SnippetsScreen(initialSection: AutomationSection.runbooks)),
    );
    await tester.pumpAndSettle();
  }

  bool shown(String id) =>
      find.byKey(Key('runbook_tile_$id')).evaluate().isNotEmpty;

  testWidgets('the context column filters runbooks by tag', (tester) async {
    await pumpLibrary(tester, const Size(1500, 900));
    expect(
      [shown('a'), shown('b'), shown('c'), shown('d')],
      [true, true, true, true],
    );

    // Tags are listed with how many runbooks carry each.
    expect(find.byKey(const Key('runbooks_filter_ops')), findsOneWidget);
    expect(find.byKey(const Key('runbooks_filter_release')), findsOneWidget);
    expect(find.byKey(const Key('runbooks_filter_perf')), findsOneWidget);

    await tester.tap(find.byKey(const Key('runbooks_filter_ops')));
    await tester.pumpAndSettle();
    expect(
      [shown('a'), shown('b'), shown('c'), shown('d')],
      [true, true, false, false],
    );

    await tester.tap(find.byKey(const Key('runbooks_filter_perf')));
    await tester.pumpAndSettle();
    expect([shown('a'), shown('b'), shown('c')], [false, false, true]);

    await tester.tap(find.byKey(const Key('runbooks_filter_all')));
    await tester.pumpAndSettle();
    expect(shown('d'), isTrue);
  });

  testWidgets('narrow widths get the same filter as chips', (tester) async {
    await pumpLibrary(tester, const Size(500, 900));
    await tester.tap(find.byKey(const Key('runbooks_chip_release')));
    await tester.pumpAndSettle();
    expect([shown('a'), shown('b'), shown('c')], [true, false, false]);
  });

  testWidgets('search matches a runbook by its tags', (tester) async {
    await pumpLibrary(tester, const Size(1500, 900));
    await tester.enterText(
      find.byKey(const Key('runbooks_search_field')),
      'perf',
    );
    await tester.pumpAndSettle();
    expect(
      [shown('a'), shown('b'), shown('c'), shown('d')],
      [false, false, true, false],
    );
  });

  testWidgets('the filter and the search combine', (tester) async {
    await pumpLibrary(tester, const Size(1500, 900));
    await tester.tap(find.byKey(const Key('runbooks_filter_ops')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('runbooks_search_field')),
      'logs',
    );
    await tester.pumpAndSettle();
    expect([shown('a'), shown('b')], [false, true]);
  });

  testWidgets('the editor saves tags from a comma separated field', (
    tester,
  ) async {
    RunbookModel? saved;
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final existing = (await RunbooksRepository(
      db.runbooksDao,
    ).getAllRunbooks()).firstWhere((r) => r.id == 'a');
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => saved = await RunbookEditorDialog.show(
                context,
                runbook: existing.copyWith(steps: const []),
                workspaceId: 'default',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Existing tags are shown.
    expect(find.text('ops, release'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('runbook_tags_field')),
      ' ops , , prod ,',
    );
    await tester.tap(find.byKey(const Key('runbook_add_step_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('step_command_'),
      ),
      'uptime',
    );
    await tester.tap(find.byKey(const Key('runbook_save_button')));
    await tester.pumpAndSettle();

    expect(saved!.tags, ['ops', 'prod']);
  });
}
