import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_models.dart';
import 'package:shellvibe/features/mcp/presentation/dialogs/mcp_runbook_approval_dialog.dart';

RunbookApprovalRequest _request({
  bool prod = true,
  List<RunbookSecretField> secrets = const [
    RunbookSecretField(name: 'token', label: 'API token'),
  ],
}) => RunbookApprovalRequest(
  clientId: 'c1',
  clientName: 'Claude Code',
  runbookTitle: 'Release API',
  strategyLabel: 'rolling',
  variables: const {'env': 'production'},
  secretFields: secrets,
  steps: const [
    RunbookApprovalStep(
      order: 1,
      kind: 'command',
      text: 'systemctl restart api',
    ),
    RunbookApprovalStep(
      order: 2,
      kind: 'approval',
      text: 'Check the dashboards',
    ),
    RunbookApprovalStep(order: 3, kind: 'snippet', text: 'echo done'),
  ],
  hosts: [
    RunbookApprovalHost(
      id: 'h1',
      label: 'web-1',
      environment: prod ? HostEnvironment.prod : HostEnvironment.dev,
    ),
    const RunbookApprovalHost(
      id: 'h2',
      label: 'web-2',
      environment: HostEnvironment.staging,
    ),
  ],
);

void main() {
  RunbookApprovalDecision? decision;
  var answered = false;

  Future<void> open(
    WidgetTester tester,
    RunbookApprovalRequest request, {
    Duration expiresIn = const Duration(minutes: 2),
  }) async {
    decision = null;
    answered = false;
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
                onPressed: () async {
                  decision = await McpRunbookApprovalDialog.show(
                    context,
                    request: request,
                    expiresAt: DateTime.now().toUtc().add(expiresIn),
                  );
                  answered = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows who asked, every step, every host with its environment, '
      'the strategy and the values', (tester) async {
    await open(tester, _request());

    expect(
      find.textContaining('Claude Code wants to run "Release API"'),
      findsOneWidget,
    );
    expect(find.text('Hosts · rolling'), findsOneWidget);
    expect(find.byKey(const Key('mcp_runbook_host_h1')), findsOneWidget);
    expect(find.byKey(const Key('mcp_runbook_host_h2')), findsOneWidget);
    expect(find.text('prod'), findsOneWidget);
    expect(find.text('staging'), findsOneWidget);
    for (final n in [1, 2, 3]) {
      expect(find.byKey(Key('mcp_runbook_step_$n')), findsOneWidget);
    }
    expect(find.text('systemctl restart api'), findsOneWidget);
    expect(find.text('2. Waits for you to continue'), findsOneWidget);
    expect(find.text('Check the dashboards'), findsOneWidget);
    expect(find.text('env = production'), findsOneWidget);
  });

  testWidgets('production is called out and the approve button says so', (
    tester,
  ) async {
    await open(tester, _request());
    final banner = find.byKey(const Key('mcp_runbook_prod_banner'));
    expect(banner, findsOneWidget);
    expect(
      find.descendant(of: banner, matching: find.textContaining('web-1')),
      findsOneWidget,
    );
    expect(find.text('Run on production'), findsOneWidget);
  });

  testWidgets('without production there is no banner and a plain Approve', (
    tester,
  ) async {
    await open(tester, _request(prod: false));
    expect(find.byKey(const Key('mcp_runbook_prod_banner')), findsNothing);
    expect(find.text('Approve'), findsOneWidget);
  });

  testWidgets('a secret is typed here, obscured, and returned only with an '
      'approval', (tester) async {
    await open(tester, _request());

    final field = find.byKey(const Key('mcp_runbook_secret_token'));
    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.obscureText, isTrue);
    expect(editable.autocorrect, isFalse);
    expect(editable.enableSuggestions, isFalse);

    // Required: approving with it empty is refused in the dialog.
    await tester.tap(find.byKey(const Key('mcp_runbook_approve_button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('mcp_runbook_secret_error_token')),
      findsOneWidget,
    );
    expect(answered, isFalse);

    await tester.enterText(field, 'hunter2');
    await tester.tap(find.byKey(const Key('mcp_runbook_approve_button')));
    await tester.pumpAndSettle();
    expect(decision!.approved, isTrue);
    expect(decision!.secretValues, {'token': 'hunter2'});
  });

  testWidgets('an optional secret may stay empty', (tester) async {
    await open(
      tester,
      _request(
        secrets: const [
          RunbookSecretField(name: 'pw', label: 'Password', required: false),
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('mcp_runbook_approve_button')));
    await tester.pumpAndSettle();
    expect(decision!.approved, isTrue);
    expect(decision!.secretValues, isEmpty);
  });

  testWidgets('Deny refuses and returns no secrets', (tester) async {
    await open(tester, _request());
    await tester.enterText(
      find.byKey(const Key('mcp_runbook_secret_token')),
      'hunter2',
    );
    await tester.tap(find.byKey(const Key('mcp_runbook_deny_button')));
    await tester.pumpAndSettle();
    expect(decision!.approved, isFalse);
    expect(decision!.secretValues, isEmpty);
  });

  testWidgets('running out the countdown refuses', (tester) async {
    await open(
      tester,
      _request(secrets: const []),
      expiresIn: const Duration(seconds: 2),
    );
    // The deadline is wall-clock, so let real time pass, then tick the timer.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2200)),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(answered, isTrue);
    expect(decision!.approved, isFalse);
  });
}
