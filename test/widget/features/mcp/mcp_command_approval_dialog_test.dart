import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/app/widgets/shellvibe_ui.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_models.dart';
import 'package:shellvibe/features/mcp/presentation/dialogs/mcp_command_approval_dialog.dart';

CommandApprovalRequest _request(String command) => CommandApprovalRequest(
  clientId: 'c1',
  clientName: 'Claude Code',
  hostId: 'h1',
  hostLabel: 'web-1',
  environment: HostEnvironment.dev,
  command: command,
  cwd: '/srv/app',
  category: RiskCategory.unclassified,
  canRemember: true,
);

void main() {
  group('visibleControlChars', () {
    test('marks line breaks and tabs, keeps ordinary text', () {
      expect(visibleControlChars('a b\tc\nd'), 'a b⇥c⏎\nd');
    });

    test('shows invisible and control characters as code points', () {
      expect(
        visibleControlChars('x${String.fromCharCode(0x202E)}y'),
        'x⟨U+202E⟩y',
      );
      expect(
        visibleControlChars('x${String.fromCharCode(0x200B)}y'),
        'x⟨U+200B⟩y',
      );
      expect(
        visibleControlChars('x${String.fromCharCode(0x2028)}y'),
        'x⟨U+2028⟩y',
      );
      expect(visibleControlChars('x\ry'), 'x⟨U+000D⟩y');
    });
  });

  Future<void> open(WidgetTester tester, String command) async {
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
          home: Scaffold(
            body: McpCommandApprovalDialog(
              request: _request(command),
              expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 2)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows every line of a multi-line command and warns', (
    tester,
  ) async {
    await open(tester, 'echo first\necho second');

    final shown = tester
        .widget<SelectableText>(find.byKey(const Key('mcp_command_text')))
        .data!;
    expect(shown, contains('echo first⏎'));
    expect(shown, contains('echo second'));
    expect(
      find.byKey(const Key('mcp_command_multiline_warning')),
      findsOneWidget,
    );
  });

  testWidgets('a single-line command gets no multi-line warning', (
    tester,
  ) async {
    await open(tester, 'uptime');
    expect(
      find.byKey(const Key('mcp_command_multiline_warning')),
      findsNothing,
    );
  });

  testWidgets('approve stays off until the arming delay has passed', (
    tester,
  ) async {
    await open(tester, 'uptime');
    final approve = find.byKey(const Key('mcp_command_approve_button'));

    expect(tester.widget<ShellVibeButton>(approve).onPressed, isNull);
    await tester.pump(mcpApprovalArmDelay);
    expect(tester.widget<ShellVibeButton>(approve).onPressed, isNotNull);
  });
}
