import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/templates/data/repositories/templates_repository.dart';
import 'package:shellvibe/features/templates/presentation/widgets/template_editor_panel.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.runbooksDao.insertRunbook(
      RunbooksCompanion.insert(
        id: 'rb',
        workspaceId: 'default',
        title: 'Health check',
        createdAt: DateTime(2026),
      ),
    );
    await db.templatesDao.insertTemplate(
      TemplatesCompanion.insert(
        id: 'tpl',
        workspaceId: 'default',
        name: 'Prod triage',
        createdAt: DateTime(2026),
      ),
    );
  });

  tearDown(() => db.close());

  Future<void> open(WidgetTester tester) async {
    final template = (await TemplatesRepository(
      db.templatesDao,
    ).getAllTemplates()).single;
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
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => TemplateEditorPanel.show(context, template),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the on-open runbook and the ask-first switch are saved', (
    tester,
  ) async {
    await open(tester);

    // Nothing chosen yet: no switch to flip.
    expect(
      find.byKey(const Key('template_editor_on_open_confirm')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('template_editor_on_open_runbook')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Health check').last);
    await tester.pumpAndSettle();

    final confirm = find.byKey(const Key('template_editor_on_open_confirm'));
    expect(tester.widget<SwitchListTile>(confirm).value, isTrue);
    await tester.tap(confirm);
    await tester.pump();

    await tester.tap(find.byKey(const Key('template_editor_save')));
    await tester.pumpAndSettle();

    final saved = (await db.select(db.templates).get()).single;
    expect(saved.onOpenRunbookId, 'rb');
    expect(saved.onOpenConfirm, isFalse);
  });

  testWidgets('choosing "no runbook" clears it', (tester) async {
    await (db.update(
      db.templates,
    )).write(const TemplatesCompanion(onOpenRunbookId: Value('rb')));
    await open(tester);

    await tester.tap(find.byKey(const Key('template_editor_on_open_runbook')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run no runbook').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('template_editor_save')));
    await tester.pumpAndSettle();

    expect(
      (await db.select(db.templates).get()).single.onOpenRunbookId,
      isNull,
    );
  });
}
