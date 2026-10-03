import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_models.dart';
import 'package:shellvibe/features/mcp/domain/services/approval_coordinator.dart';

const _request = RunbookApprovalRequest(
  clientId: 'client-1',
  clientName: 'Claude Desktop',
  runbookTitle: 'Deploy',
  steps: [RunbookApprovalStep(order: 1, kind: 'command', text: 'uptime')],
  hosts: [
    RunbookApprovalHost(
      id: 'h1',
      label: 'prod-web-01',
      environment: HostEnvironment.prod,
    ),
  ],
  strategyLabel: 'parallel ×4',
);

void main() {
  late ApprovalCoordinator coordinator;

  setUp(() => coordinator = ApprovalCoordinator());
  tearDown(() => coordinator.dispose());

  test('an unanswered runbook approval resolves as denied', () async {
    final decision = await coordinator.requestRunbookApproval(
      _request,
      timeout: const Duration(milliseconds: 40),
    );
    expect(decision.approved, isFalse);
    expect(coordinator.currentRunbooks, isEmpty);
  });

  test('the UI answer completes the request, secret values and all', () async {
    final future = coordinator.requestRunbookApproval(_request);
    final pending = coordinator.currentRunbooks.single;
    expect(pending.request.runbookTitle, 'Deploy');

    coordinator.resolveRunbook(
      pending.id,
      const RunbookApprovalDecision(
        approved: true,
        secretValues: {'token': 's3cret'},
      ),
    );
    final decision = await future;
    expect(decision.approved, isTrue);
    expect(decision.secretValues, {'token': 's3cret'});
    expect(coordinator.currentRunbooks, isEmpty);
  });

  test(
    'cancelAll (vault lock, panic) refuses a pending runbook approval',
    () async {
      final future = coordinator.requestRunbookApproval(_request);
      coordinator.cancelAll();
      expect((await future).approved, isFalse);
    },
  );

  test('the pending list is announced to the UI', () async {
    final seen = <int>[];
    final sub = coordinator.pendingRunbooks.listen((l) => seen.add(l.length));
    final future = coordinator.requestRunbookApproval(_request);
    coordinator.resolveRunbook(
      coordinator.currentRunbooks.single.id,
      RunbookApprovalDecision.denied,
    );
    await future;
    await Future<void>.delayed(Duration.zero);
    expect(seen, [1, 0]);
    await sub.cancel();
  });

  test('answering twice, or an unknown id, changes nothing', () async {
    final future = coordinator.requestRunbookApproval(_request);
    final id = coordinator.currentRunbooks.single.id;
    coordinator.resolveRunbook(
      id,
      const RunbookApprovalDecision(approved: true),
    );
    coordinator.resolveRunbook(id, RunbookApprovalDecision.denied);
    coordinator.resolveRunbook('nope', RunbookApprovalDecision.denied);
    expect((await future).approved, isTrue);
  });
}
