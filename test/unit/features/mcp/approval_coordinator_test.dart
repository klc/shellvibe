import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_models.dart';
import 'package:shellvibe/features/mcp/domain/services/approval_coordinator.dart';

CommandApprovalRequest _commandRequest({bool canRemember = true}) {
  return CommandApprovalRequest(
    clientId: 'client-1',
    clientName: 'Claude Desktop',
    hostId: 'host-1',
    hostLabel: 'prod-web-01',
    environment: HostEnvironment.prod,
    command: 'rm -rf ./logs/*.gz',
    cwd: '/var/log',
    category: RiskCategory.destructiveFs,
    canRemember: canRemember,
  );
}

HostAccessRequest _hostAccessRequest() {
  return const HostAccessRequest(
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
      HostAccessCandidate(
        hostId: 'host-2',
        label: 'staging-api',
        environment: HostEnvironment.staging,
        suggestedMode: McpAccessMode.guarded,
      ),
    ],
  );
}

void main() {
  late ApprovalCoordinator coordinator;

  setUp(() => coordinator = ApprovalCoordinator());
  tearDown(() => coordinator.dispose());

  group('fail-closed timeouts', () {
    test('an unanswered command approval resolves as denied', () async {
      final future = coordinator.requestCommandApproval(
        _commandRequest(),
        timeout: const Duration(milliseconds: 40),
      );

      final decision = await future;
      expect(decision.approved, isFalse);
    });

    test('an unanswered host-access request denies every candidate with reason '
        'timeout', () async {
      final request = _hostAccessRequest();
      final result = await coordinator.requestHostAccess(
        request,
        timeout: const Duration(milliseconds: 40),
      );

      expect(result.granted, isEmpty);
      expect(result.denied.length, request.candidates.length);
      expect(result.denied.map((d) => d.reason).toSet(), {'timeout'});
      expect(result.denied.map((d) => d.hostId).toSet(), {'host-1', 'host-2'});
    });

    test('a timed-out request is dropped from the pending list', () async {
      await coordinator.requestCommandApproval(
        _commandRequest(),
        timeout: const Duration(milliseconds: 40),
      );
      expect(coordinator.currentCommands, isEmpty);
    });
  });

  group('resolveCommand', () {
    test('an approval is returned to the caller with its scope', () async {
      final future = coordinator.requestCommandApproval(_commandRequest());
      final pending = coordinator.currentCommands.single;

      coordinator.resolveCommand(
        pending.id,
        const ApprovalDecision(
          approved: true,
          scope: ApprovalScope.fifteenMinutes,
        ),
      );

      final decision = await future;
      expect(decision.approved, isTrue);
      expect(decision.scope, ApprovalScope.fifteenMinutes);
    });

    test('a scope wider than once is forced down to once when the request may '
        'not be remembered — the coordinator does not trust the UI to have '
        'greyed the option out', () async {
      final future = coordinator.requestCommandApproval(
        _commandRequest(canRemember: false),
      );
      final pending = coordinator.currentCommands.single;

      coordinator.resolveCommand(
        pending.id,
        const ApprovalDecision(approved: true, scope: ApprovalScope.always),
      );

      final decision = await future;
      expect(decision.approved, isTrue, reason: 'the answer still stands');
      expect(decision.scope, ApprovalScope.once);
    });

    test('a refusal is passed through unchanged', () async {
      final future = coordinator.requestCommandApproval(_commandRequest());
      final pending = coordinator.currentCommands.single;

      coordinator.resolveCommand(pending.id, ApprovalDecision.denied);

      final decision = await future;
      expect(decision.approved, isFalse);
    });

    test('resolving an unknown id is a no-op rather than a crash', () {
      expect(
        () => coordinator.resolveCommand('no-such-id', ApprovalDecision.denied),
        returnsNormally,
      );
    });

    test('a second resolve for the same id is ignored', () async {
      final future = coordinator.requestCommandApproval(_commandRequest());
      final pending = coordinator.currentCommands.single;

      coordinator.resolveCommand(
        pending.id,
        const ApprovalDecision(approved: true),
      );
      // Would throw on a completed Completer if the guard were missing.
      coordinator.resolveCommand(pending.id, ApprovalDecision.denied);

      expect((await future).approved, isTrue);
    });
  });

  group('resolveHostAccess', () {
    test(
      'partial approval grants some candidates and denies the rest',
      () async {
        final future = coordinator.requestHostAccess(_hostAccessRequest());
        final pending = coordinator.currentHostAccess.single;

        coordinator.resolveHostAccess(
          pending.id,
          const HostAccessResult(
            granted: [
              HostAccessGrant(hostId: 'host-1', mode: McpAccessMode.readonly),
            ],
            denied: [HostAccessDenial(hostId: 'host-2', reason: 'user_denied')],
          ),
        );

        final result = await future;
        expect(result.granted.single.hostId, 'host-1');
        expect(result.granted.single.mode, McpAccessMode.readonly);
        expect(result.denied.single.hostId, 'host-2');
        expect(result.denied.single.reason, 'user_denied');
      },
    );

    test('each granted candidate keeps its own mode', () async {
      final future = coordinator.requestHostAccess(_hostAccessRequest());
      final pending = coordinator.currentHostAccess.single;

      coordinator.resolveHostAccess(
        pending.id,
        const HostAccessResult(
          granted: [
            HostAccessGrant(hostId: 'host-1', mode: McpAccessMode.readonly),
            HostAccessGrant(hostId: 'host-2', mode: McpAccessMode.guarded),
          ],
          denied: [],
        ),
      );

      final byHost = {for (final g in (await future).granted) g.hostId: g.mode};
      expect(byHost, {
        'host-1': McpAccessMode.readonly,
        'host-2': McpAccessMode.guarded,
      });
    });
  });

  group('pending streams', () {
    test('a registered request appears in the pending list', () {
      coordinator.requestCommandApproval(_commandRequest());
      expect(coordinator.currentCommands.length, 1);
      expect(
        coordinator.currentCommands.single.request.command,
        'rm -rf ./logs/*.gz',
      );
    });

    test('expiresAt reflects the requested timeout', () {
      coordinator.requestCommandApproval(
        _commandRequest(),
        timeout: const Duration(seconds: 120),
      );
      final pending = coordinator.currentCommands.single;
      final window = pending.expiresAt.difference(pending.requestedAt);
      expect(window, const Duration(seconds: 120));
    });

    test(
      'the pending stream emits on registration and on resolution',
      () async {
        final seen = <int>[];
        final sub = coordinator.pendingCommands.listen(
          (l) => seen.add(l.length),
        );

        coordinator.requestCommandApproval(_commandRequest());
        await Future<void>.delayed(Duration.zero);
        final id = coordinator.currentCommands.single.id;
        coordinator.resolveCommand(id, ApprovalDecision.denied);
        await Future<void>.delayed(Duration.zero);

        await sub.cancel();
        expect(seen, containsAllInOrder([1, 0]));
      },
    );
  });

  group('cancelAll', () {
    test('resolves every pending command as denied', () async {
      final a = coordinator.requestCommandApproval(_commandRequest());
      final b = coordinator.requestCommandApproval(_commandRequest());

      coordinator.cancelAll();

      expect((await a).approved, isFalse);
      expect((await b).approved, isFalse);
      expect(coordinator.currentCommands, isEmpty);
    });

    test('denies every pending host-access candidate', () async {
      final future = coordinator.requestHostAccess(_hostAccessRequest());

      coordinator.cancelAll();

      final result = await future;
      expect(result.granted, isEmpty);
      expect(result.denied.length, 2);
      expect(result.denied.map((d) => d.reason).toSet(), {'cancelled'});
    });
  });

  test('dispose resolves anything still pending rather than hanging', () async {
    final coordinator = ApprovalCoordinator();
    final future = coordinator.requestCommandApproval(_commandRequest());

    coordinator.dispose();

    expect((await future).approved, isFalse);
  });
}
