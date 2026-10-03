import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/features/snippets/domain/models/runbook_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_step_model.dart';
import 'package:shellvibe/features/snippets/presentation/widgets/runbook_editor_dialog.dart';

void main() {
  testWidgets('per-step failure policy and retries are edited and saved, and '
      'the default targets are kept', (tester) async {
    final runbook = RunbookModel(
      id: 'rb',
      workspaceId: 'default',
      title: 'Deploy',
      createdAt: DateTime(2026),
      defaultHostIds: const ['h1'],
      steps: const [
        RunbookStepModel(
          id: 's1',
          runbookId: 'rb',
          stepOrder: 1,
          command: 'uptime',
        ),
      ],
    );
    RunbookModel? saved;
    await tester.pumpWidget(
      ShadTheme(
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
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('step_retries_s1')), '3');
    await tester.tap(find.byKey(const ValueKey('step_on_failure_s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('runbook_save_button')));
    await tester.pumpAndSettle();

    final step = saved!.steps.single;
    expect(step.retries, 3);
    expect(step.onFailure, StepFailurePolicy.continueRun);
    expect(saved!.defaultHostIds, ['h1']);
  });

  testWidgets('retries outside 0-5 are rejected', (tester) async {
    await tester.pumpWidget(
      ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.light(),
          brightness: Brightness.light,
        ),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => RunbookEditorDialog.show(
                  context,
                  runbook: RunbookModel(
                    id: 'rb',
                    workspaceId: 'default',
                    title: 'Deploy',
                    createdAt: DateTime(2026),
                    steps: const [
                      RunbookStepModel(
                        id: 's1',
                        runbookId: 'rb',
                        stepOrder: 1,
                        command: 'uptime',
                      ),
                    ],
                  ),
                  workspaceId: 'default',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('step_retries_s1')), '9');
    await tester.tap(find.byKey(const Key('runbook_save_button')));
    await tester.pumpAndSettle();
    expect(find.text('0 to 5'), findsOneWidget);
    // Still open: nothing was saved.
    expect(find.byKey(const Key('runbook_save_button')), findsOneWidget);
  });
}
