import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/router/app_router.dart';
import 'package:shellvibe/features/mcp/data/mcp_providers.dart';
import 'package:shellvibe/features/mcp/data/mcp_session_pool.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_client_repository.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_grant_repository.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_repository_providers.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_models.dart';
import 'package:shellvibe/features/mcp/domain/services/approval_coordinator.dart';
import 'package:shellvibe/features/mcp/domain/services/mcp_service_providers.dart';
import 'package:shellvibe/features/mcp/presentation/dialogs/mcp_command_approval_dialog.dart'
    show mcpApprovalArmDelay;
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
Widget _harness(
  ApprovalCoordinator coordinator, {
  GlobalKey<NavigatorState>? navigatorKey,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      approvalCoordinatorProvider.overrideWithValue(coordinator),
      ...overrides,
    ],
    child: ShadApp(
      navigatorKey: navigatorKey ?? rootNavigatorKey,
      home: const Scaffold(body: SizedBox.shrink()),
      builder: (context, child) =>
          McpApprovalHost(child: child ?? const SizedBox.shrink()),
    ),
  );
}

/// Records the revoke and holds it open until [release] completes, so the
/// host is observably "mid-suspend".
class _FakeClientRepo extends Fake implements McpClientRepository {
  final revoked = <String>[];
  final release = Completer<void>();

  @override
  Future<void> revokeClient(String id) async {
    revoked.add(id);
    await release.future;
  }
}

class _FakePool extends Fake implements McpSessionPool {
  final closed = <String>[];

  @override
  Future<void> closeForClient(String clientId) async => closed.add(clientId);
}

class _FakeGrants extends Fake implements McpGrantRepository {
  final revoked = <String>[];

  @override
  Future<void> revokeAllForClient(String clientId) async =>
      revoked.add(clientId);
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
    _ignoreOverflow(tester);

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
    expect(tester.widget<ShellVibeButton>(approveButton).onPressed, isNull);
    await tester.pump(mcpApprovalArmDelay);
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

  testWidgets('a request seen while the navigator is missing does not wedge '
      'the host', (tester) async {
    _ignoreOverflow(tester);
    // The host is mounted but `rootNavigatorKey` has no navigator yet.
    await tester.pumpWidget(
      _harness(coordinator, navigatorKey: GlobalKey<NavigatorState>()),
    );
    await tester.pump();
    unawaited(coordinator.requestHostAccess(_hostAccessRequest()));
    await _pumpFrames(tester);

    // Navigator becomes reachable; the next request must get its dialog.
    await tester.pumpWidget(_harness(coordinator));
    await tester.pump();
    unawaited(coordinator.requestHostAccess(_hostAccessRequest()));
    await _pumpFrames(tester);

    expect(
      find.byKey(const Key('mcp_host_access_approve_button')),
      findsOneWidget,
    );
    coordinator.cancelAll(); // clears the pending fail-closed timers
    await _pumpFrames(tester);
  });

  testWidgets('deny and suspend does not pop the page under the dialog', (
    tester,
  ) async {
    _ignoreOverflow(tester);
    final clients = _FakeClientRepo();
    await tester.pumpWidget(
      _harness(
        coordinator,
        overrides: [
          mcpClientRepositoryProvider.overrideWithValue(clients),
          mcpSessionPoolProvider.overrideWithValue(_FakePool()),
          mcpGrantRepositoryProvider.overrideWithValue(_FakeGrants()),
        ],
      ),
    );
    await tester.pump();
    unawaited(
      rootNavigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('user page')),
      ),
    );
    await _pumpFrames(tester);

    unawaited(coordinator.requestHostAccess(_hostAccessRequest()));
    await _pumpFrames(tester);
    final suspend = find.byKey(
      const Key('mcp_host_access_deny_suspend_button'),
    );
    await tester.pump(mcpApprovalArmDelay);
    tester.widget<ShellVibeButton>(suspend).onPressed!();
    // The revoke is still running while the coordinator's update arrives.
    await _pumpFrames(tester);
    expect(clients.revoked, ['client-1']);
    expect(find.text('user page'), findsOneWidget);

    clients.release.complete();
    await _pumpFrames(tester);
    expect(find.text('user page'), findsOneWidget);
  });

  testWidgets('deny and suspend also closes the client\'s sessions and grants', (
    tester,
  ) async {
    _ignoreOverflow(tester);
    final clients = _FakeClientRepo()..release.complete();
    final pool = _FakePool();
    final grants = _FakeGrants();
    await tester.pumpWidget(
      _harness(
        coordinator,
        overrides: [
          mcpClientRepositoryProvider.overrideWithValue(clients),
          mcpSessionPoolProvider.overrideWithValue(pool),
          mcpGrantRepositoryProvider.overrideWithValue(grants),
        ],
      ),
    );
    await tester.pump();

    unawaited(coordinator.requestHostAccess(_hostAccessRequest()));
    await _pumpFrames(tester);
    await tester.pump(mcpApprovalArmDelay);
    tester
        .widget<ShellVibeButton>(
          find.byKey(const Key('mcp_host_access_deny_suspend_button')),
        )
        .onPressed!();
    await _pumpFrames(tester);

    expect(clients.revoked, ['client-1']);
    expect(pool.closed, ['client-1']);
    expect(grants.revoked, ['client-1']);
  });
}

/// The test binding renders every glyph as a full-em block, so the dialog's
/// fixed-width rows overflow here in a way they do not with the app's real
/// fonts. That is a rendering artifact of the harness, not the behaviour
/// under test.
void _ignoreOverflow(WidgetTester tester) {
  final reportError = FlutterError.onError!;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
      return;
    }
    reportError(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
}

/// Advances enough frames for a dialog route to finish animating in or out,
/// without waiting for a tree that never settles (the countdown ticker).
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
