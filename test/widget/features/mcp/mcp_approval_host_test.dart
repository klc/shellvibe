import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/router/app_router.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_models.dart';
import 'package:shellvibe/features/mcp/domain/services/approval_coordinator.dart';
import 'package:shellvibe/features/mcp/domain/services/mcp_service_providers.dart';
import 'package:shellvibe/features/mcp/presentation/widgets/mcp_approval_host.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/app/widgets/shellvibe_ui.dart';

HostAccessRequest _hostAccessRequest() => const HostAccessRequest(
  clientId: 'client-1',
  clientName: 'Claude Desktop',
  reason: 'Investigating a disk-full alert',
  candidates: [
    HostAccessCandidate(
      hostId: 'host-1',
      label: 'prod-web-01',
      environment: HostEnvironment.prod,
      suggestedMode: McpAccessMode.readonly,
    ),
  ],
);

/// Mirrors how `ShellVibeApp` mounts the host: above the router's Navigator,
/// which is the only Navigator the widget can reach (through
/// [rootNavigatorKey]).
Widget _harness(ApprovalCoordinator coordinator) {
  return ProviderScope(
    overrides: [approvalCoordinatorProvider.overrideWithValue(coordinator)],
    child: ShadApp(
      navigatorKey: rootNavigatorKey,
      home: const Scaffold(body: SizedBox.shrink()),
      builder: (context, child) =>
          McpApprovalHost(child: child ?? const SizedBox.shrink()),
    ),
  );
}

void main() {
  late ApprovalCoordinator coordinator;

  // `bringMcpApprovalWindowForward` talks to window_manager on desktop, and
  // an unanswered platform channel never completes under the test binding's
  // fake async — the dialog would then never be reached.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => call.method == 'isMinimized' ? false : null,
        );
  });

  setUp(() => coordinator = ApprovalCoordinator());
  tearDown(() => coordinator.dispose());

  testWidgets('answering a host-access prompt leaves no second dialog behind', (
    tester,
  ) async {
    // The test binding renders every glyph as a full-em block, so the
    // dialog's fixed-width rows overflow here in a way they do not with the
    // app's real fonts. That is a rendering artifact of the harness, not the
    // behaviour under test.
    final reportError = FlutterError.onError!;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
        return;
      }
      reportError(details);
    };
    addTearDown(() => FlutterError.onError = reportError);

    await tester.pumpWidget(_harness(coordinator));
    await tester.pump();

    HostAccessResult? outcome;
    unawaited(
      coordinator
          .requestHostAccess(_hostAccessRequest())
          .then((r) => outcome = r),
    );
    // Not pumpAndSettle: the dialog runs a one-second countdown ticker, so
    // the tree never goes quiet while it is on screen.
    await _pumpFrames(tester);

    final approveButton = find.byKey(
      const Key('mcp_host_access_approve_button'),
    );
    expect(approveButton, findsOneWidget);

    // Invoked rather than tapped: the artificial overflow above pushes the
    // button outside the dialog's own bounds, so a hit test at its centre
    // lands on the barrier instead. What this test is about is what the host
    // does *after* the dialog is answered.
    tester.widget<ShellVibeButton>(approveButton).onPressed!();
    await _pumpFrames(tester);

    // The agent gets its answer...
    expect(outcome?.granted, hasLength(1));

    // ...and the prompt is gone. Before the fix, the coordinator's broadcast
    // stream had not yet delivered the updated pending list, so the host
    // re-claimed the request it had just resolved and put an identical
    // second dialog on screen, which the user had to dismiss again.
    expect(approveButton, findsNothing);
  });
}

/// Advances enough frames for a dialog route to finish animating in or out,
/// without waiting for a tree that never settles (the countdown ticker).
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
