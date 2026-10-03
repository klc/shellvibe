import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/features/snippets/domain/models/runbook_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_step_model.dart';
import 'package:shellvibe/features/snippets/presentation/widgets/runbook_editor_dialog.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

RunbookStepModel _step(
  String id,
  int order,
  String command, {
  StepKind kind = StepKind.command,
  String? snippetId,
}) => RunbookStepModel(
  id: id,
  runbookId: 'rb',
  stepOrder: order,
  command: command,
  kind: kind,
  snippetId: snippetId,
);

RunbookModel _runbook(List<RunbookStepModel> steps) => RunbookModel(
  id: 'rb',
  workspaceId: 'default',
  title: 'Deploy',
  createdAt: DateTime(2026),
  defaultHostIds: const ['h1'],
  tags: const ['ops'],
  steps: steps,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  RunbookModel? saved;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    saved = null;
    await db.snippetsDao.insertSnippet(
      SnippetsCompanion.insert(
        id: 'sn',
        workspaceId: 'default',
        title: 'Restart app',
        code: r'systemctl restart app ${INPUT:unit}',
        tags: const Value('["ops"]'),
      ),
    );
    await db.snippetsDao.insertSnippet(
      SnippetsCompanion.insert(
        id: 'sn2',
        workspaceId: 'default',
        title: 'Disk usage',
        code: 'df -h',
      ),
    );
  });

  tearDown(() => db.close());

  Future<void> open(WidgetTester tester, {RunbookModel? runbook}) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
                  onPressed: () async => saved = await RunbookEditorDialog.show(
                    context,
                    runbook: runbook,
                    workspaceId: 'default',
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

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('runbook_save_button')));
    await tester.pumpAndSettle();
  }

  testWidgets('per-step failure policy and retries are edited and saved, and '
      'the default targets and tags are kept', (tester) async {
    await open(tester, runbook: _runbook([_step('s1', 1, 'uptime')]));

    await tester.enterText(find.byKey(const ValueKey('step_retries_s1')), '3');
    await tester.tap(find.byKey(const ValueKey('step_on_failure_s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue').last);
    await tester.pumpAndSettle();
    await save(tester);

    final step = saved!.steps.single;
    expect(step.retries, 3);
    expect(step.onFailure, StepFailurePolicy.continueRun);
    expect(saved!.defaultHostIds, ['h1']);
    expect(saved!.tags, ['ops']);
  });

  testWidgets('retries outside 0-5 are rejected inline', (tester) async {
    await open(tester, runbook: _runbook([_step('s1', 1, 'uptime')]));
    await tester.enterText(find.byKey(const ValueKey('step_retries_s1')), '9');
    await save(tester);
    expect(find.text('0 to 5'), findsOneWidget);
    expect(saved, isNull);
    expect(find.byKey(const Key('runbook_save_button')), findsOneWidget);
  });

  testWidgets('saving with no steps says so by the step list, not in an '
      'alert', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('runbook_title_field')), 'T');
    await save(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('runbook_steps_error'))).data,
      'Runbook must have at least 1 step.',
    );
    expect(saved, isNull);
  });

  testWidgets('a step can be turned into an approval gate with a message', (
    tester,
  ) async {
    await open(
      tester,
      runbook: _runbook([_step('s1', 1, 'uptime'), _step('s2', 2, '')]),
    );
    await tester.tap(find.byKey(const Key('step_kind_s2_approval')));
    await tester.pumpAndSettle();
    // A gate has no exit code or retries.
    expect(find.byKey(const ValueKey('step_retries_s2')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('step_message_s2')),
      'Check the dashboards',
    );
    await save(tester);

    final gate = saved!.steps[1];
    expect(gate.kind, StepKind.approval);
    expect(gate.command, 'Check the dashboards');
    expect(saved!.steps[0].kind, StepKind.command);
  });

  testWidgets('an empty approval message is refused inline', (tester) async {
    await open(tester, runbook: _runbook([_step('s1', 1, '')]));
    await tester.tap(find.byKey(const Key('step_kind_s1_approval')));
    await tester.pumpAndSettle();
    await save(tester);
    expect(find.text('A message is required'), findsOneWidget);
    expect(saved, isNull);
  });

  testWidgets('a snippet step is chosen from a searchable list and shows '
      'its code read-only', (tester) async {
    await open(tester, runbook: _runbook([_step('s1', 1, '')]));
    await tester.tap(find.byKey(const Key('step_kind_s1_snippet')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('step_snippet_hint_s1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('step_snippet_pick_s1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('step_snippet_search')),
      'disk',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('step_snippet_option_sn')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('step_snippet_search')),
      'restart',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('step_snippet_option_sn2')), findsNothing);
    await tester.tap(find.byKey(const Key('step_snippet_option_sn')));
    await tester.pumpAndSettle();

    final code = find.byKey(const Key('step_snippet_code_s1'));
    expect(code, findsOneWidget);
    expect(
      find.descendant(
        of: code,
        matching: find.textContaining('systemctl restart app'),
      ),
      findsOneWidget,
    );
    // The snippet's placeholder is offered under Variables.
    expect(find.byKey(const Key('variable_row_unit')), findsOneWidget);

    await save(tester);
    final step = saved!.steps.single;
    expect(step.kind, StepKind.snippet);
    expect(step.snippetId, 'sn');
    // A client that predates snippet steps then runs a comment.
    expect(step.command, '# snippet: Restart app');
  });

  testWidgets('a snippet step with no snippet is refused', (tester) async {
    await open(tester, runbook: _runbook([_step('s1', 1, '')]));
    await tester.tap(find.byKey(const Key('step_kind_s1_snippet')));
    await tester.pumpAndSettle();
    await save(tester);
    expect(saved, isNull);
  });

  testWidgets('steps move up and down with the buttons', (tester) async {
    await open(
      tester,
      runbook: _runbook([
        _step('s1', 1, 'first'),
        _step('s2', 2, 'second'),
        _step('s3', 3, 'third'),
      ]),
    );
    await tester.tap(find.byKey(const Key('step_down_s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('step_up_s3')));
    await tester.pumpAndSettle();
    await save(tester);

    expect(saved!.steps.map((s) => s.command), ['second', 'third', 'first']);
    expect(saved!.steps.map((s) => s.stepOrder), [1, 2, 3]);
    // Edits stay with their step through a move.
    expect(saved!.steps.map((s) => s.id), ['s2', 's3', 's1']);
  });

  testWidgets('a step can be dragged to a new place', (tester) async {
    await open(
      tester,
      runbook: _runbook([_step('s1', 1, 'first'), _step('s2', 2, 'second')]),
    );
    await tester.timedDrag(
      find.byKey(const Key('step_drag_s1')),
      const Offset(0, 500),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    await save(tester);
    expect(saved!.steps.map((s) => s.id), ['s2', 's1']);
  });

  testWidgets('a step is duplicated right after itself, with its settings', (
    tester,
  ) async {
    await open(
      tester,
      runbook: _runbook([
        _step('s1', 1, 'uptime').copyWith(retries: 2),
        _step('s2', 2, 'df'),
      ]),
    );
    await tester.tap(find.byKey(const Key('step_duplicate_s1')));
    await tester.pumpAndSettle();
    await save(tester);

    expect(saved!.steps.map((s) => s.command), ['uptime', 'uptime', 'df']);
    expect(saved!.steps[1].retries, 2);
    expect(saved!.steps[1].id, isNot('s1'));
    expect(saved!.steps.map((s) => s.stepOrder), [1, 2, 3]);
  });

  testWidgets('a step is removed and the rest renumbered', (tester) async {
    await open(
      tester,
      runbook: _runbook([_step('s1', 1, 'a'), _step('s2', 2, 'b')]),
    );
    await tester.tap(find.byKey(const Key('step_remove_s1')));
    await tester.pumpAndSettle();
    await save(tester);
    expect(saved!.steps.single.id, 's2');
    expect(saved!.steps.single.stepOrder, 1);
  });
}
