import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_models.dart';
import 'package:shellvibe/features/mcp/presentation/dialogs/mcp_host_add_dialog.dart';

HostAddRequest _request({String? username = 'deploy', int port = 2222}) =>
    HostAddRequest(
      clientId: 'c1',
      clientName: 'Claude Code',
      label: 'web-1',
      hostname: 'web1.example.com',
      port: port,
      username: username,
      identities: const [
        HostAddIdentity(id: 'id-root', title: 'Root key', username: 'root'),
        HostAddIdentity(id: 'id-deploy', title: 'Deploy', username: 'deploy'),
      ],
    );

void main() {
  HostAddDecision? decision;
  var answered = false;

  Future<void> open(WidgetTester tester, HostAddRequest request) async {
    decision = null;
    answered = false;
    tester.view.physicalSize = const Size(1000, 1200);
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
                  decision = await McpHostAddDialog.show(
                    context,
                    request: request,
                    expiresAt: DateTime.now().toUtc().add(
                      const Duration(minutes: 2),
                    ),
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

  testWidgets('shows who asked and the address, with no identity picked', (
    tester,
  ) async {
    await open(tester, _request());
    expect(find.textContaining('Claude Code wants to save'), findsOneWidget);
    expect(find.text('web-1'), findsOneWidget);
    expect(find.text('deploy@web1.example.com:2222'), findsOneWidget);
    expect(find.text('None (add credentials later)'), findsOneWidget);
  });

  testWidgets('Add host returns the identity the user picked', (tester) async {
    await open(tester, _request());
    await tester.tap(find.byKey(const Key('mcp_host_add_identity')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deploy (deploy)').last);
    await tester.pumpAndSettle();
    final approve = find.byKey(const Key('mcp_host_add_approve_button'));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(approve);
    await tester.pumpAndSettle();
    expect(decision?.approved, isTrue);
    expect(decision?.identityId, 'id-deploy');
  });

  testWidgets('no user name: no identity picked, default port hidden', (
    tester,
  ) async {
    await open(tester, _request(username: null, port: 22));
    expect(find.text('web1.example.com'), findsOneWidget);
    expect(find.text('None (add credentials later)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const Key('mcp_host_add_approve_button')));
    await tester.pumpAndSettle();
    expect(decision?.approved, isTrue);
    expect(decision?.identityId, isNull);
  });

  testWidgets('Deny refuses', (tester) async {
    await open(tester, _request());
    await tester.tap(find.byKey(const Key('mcp_host_add_deny_button')));
    await tester.pumpAndSettle();
    expect(answered, isTrue);
    expect(decision?.approved, isFalse);
  });
}
