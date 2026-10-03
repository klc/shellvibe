import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/features/snippets/domain/models/run_target.dart';
import 'package:shellvibe/features/snippets/presentation/widgets/run_target_sheet.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    for (final id in ['h1', 'h2', 'h3']) {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: id,
          workspaceId: 'default',
          label: 'web-$id',
          hostname: '$id.example.com',
          createdAt: DateTime(2026),
        ),
      );
    }
    await db.templatesDao.insertTemplate(
      TemplatesCompanion.insert(
        id: 'tpl',
        workspaceId: 'default',
        name: 'Prod triage',
        createdAt: DateTime(2026),
      ),
    );
    await db.templatesDao.replacePanes('tpl', [
      TemplatePanesCompanion.insert(
        id: 'p0',
        templateId: 'tpl',
        paneOrder: 0,
        sessionType: 'ssh',
        hostId: const Value('h1'),
      ),
      TemplatePanesCompanion.insert(
        id: 'p1',
        templateId: 'tpl',
        paneOrder: 1,
        sessionType: 'ssh',
        hostId: const Value('h1'),
      ),
      TemplatePanesCompanion.insert(
        id: 'p2',
        templateId: 'tpl',
        paneOrder: 2,
        sessionType: 'ssh',
        hostId: const Value('h2'),
      ),
      TemplatePanesCompanion.insert(
        id: 'p3',
        templateId: 'tpl',
        paneOrder: 3,
        sessionType: 'local',
      ),
    ]);
  });

  tearDown(() => db.close());

  Future<void> openSheet(
    WidgetTester tester,
    void Function(RunTargetSelection?) onResult,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => onResult(
                    await RunTargetSheet.show(context, subject: 'Check'),
                  ),
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

  bool checked(WidgetTester tester, String id) => tester
      .widget<CheckboxListTile>(find.byKey(Key('run_target_host_$id')))
      .value!;

  Future<void> chooseTemplate(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('run_target_template')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prod triage').last);
    await tester.pumpAndSettle();
  }

  testWidgets('choosing a template selects its distinct hosts and says what '
      'it skipped', (tester) async {
    RunTargetSelection? result;
    await openSheet(tester, (r) => result = r);

    await chooseTemplate(tester);
    expect(checked(tester, 'h1'), isTrue);
    expect(checked(tester, 'h2'), isTrue);
    expect(checked(tester, 'h3'), isFalse);
    expect(
      find.text('2 hosts selected; 1 pane skipped (local shell or no host).'),
      findsOneWidget,
    );
    expect(find.text('Run on 2 hosts'), findsOneWidget);

    // The boxes stay editable afterwards.
    await tester.tap(find.byKey(const Key('run_target_host_h2')));
    await tester.tap(find.byKey(const Key('run_target_host_h3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('run_target_confirm')));
    await tester.pumpAndSettle();

    expect(result!.hosts.map((h) => h.id).toSet(), {'h1', 'h3'});
    expect(result!.openLayoutOf, isNull);
  });

  testWidgets('"Also open the layout" returns the template', (tester) async {
    RunTargetSelection? result;
    await openSheet(tester, (r) => result = r);

    // Not offered until a template is chosen.
    expect(find.byKey(const Key('run_target_open_layout')), findsNothing);
    await chooseTemplate(tester);
    await tester.tap(find.byKey(const Key('run_target_open_layout')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('run_target_confirm')));
    await tester.pumpAndSettle();

    expect(result!.openLayoutOf!.id, 'tpl');
    expect(result!.hosts.map((h) => h.id).toSet(), {'h1', 'h2'});
  });

  testWidgets('without templates the section is not shown', (tester) async {
    await db.templatesDao.deleteTemplate('tpl');
    await openSheet(tester, (_) {});
    expect(find.byKey(const Key('run_target_template')), findsNothing);
  });
}
