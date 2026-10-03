import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_step_model.dart';
import 'package:shellvibe/features/snippets/domain/models/snippet_model.dart';
import 'package:shellvibe/features/snippets/domain/services/remote_command_session.dart';
import 'package:shellvibe/features/snippets/domain/services/runbook_run_service.dart';

HostModel host(String id) => HostModel(
  id: id,
  workspaceId: 'w',
  label: id,
  hostname: '$id.example.com',
  createdAt: DateTime(2026),
);

RunbookModel runbook(List<String> commands) => RunbookModel(
  id: 'rb',
  workspaceId: 'w',
  title: 'rb',
  createdAt: DateTime(2026),
  steps: [
    for (var i = 0; i < commands.length; i++)
      RunbookStepModel(
        id: 's$i',
        runbookId: 'rb',
        stepOrder: i + 1,
        command: commands[i],
      ),
  ],
);

/// Runs commands through [handler]; records interrupts and closes.
class FakeSession implements RemoteCommandSession {
  final Future<(String, int)> Function(String command) handler;
  final String hostId;
  final List<String> ran = [];
  int interrupts = 0;
  int closes = 0;
  final _interrupted = Completer<void>();

  FakeSession(this.hostId, this.handler);

  @override
  Future<(String, int)> run(String command, Duration timeout) {
    ran.add(command);
    return handler(command);
  }

  /// A command that never finishes on its own, only when interrupted.
  Future<(String, int)> hang() async {
    await _interrupted.future;
    return ('interrupted', 130);
  }

  @override
  Future<void> interrupt() async {
    interrupts++;
    if (!_interrupted.isCompleted) _interrupted.complete();
  }

  @override
  Future<void> close() async => closes++;
}

class FakeFactory implements RemoteCommandSessionFactory {
  final Future<(String, int)> Function(String hostId, String command)? handler;
  final Set<String> failing;
  final Duration openDelay;
  final Set<String> hanging;
  final Map<String, FakeSession> sessions = {};
  int inFlightOpens = 0;
  int maxInFlightOpens = 0;
  int opened = 0;

  FakeFactory({
    this.handler,
    this.failing = const {},
    this.hanging = const {},
    this.openDelay = Duration.zero,
  });

  @override
  Future<RemoteCommandSession> open(HostModel host) async {
    inFlightOpens++;
    if (inFlightOpens > maxInFlightOpens) maxInFlightOpens = inFlightOpens;
    try {
      await Future<void>.delayed(openDelay);
      if (failing.contains(host.id)) {
        throw const RemoteCommandException('connection refused');
      }
      opened++;
      late final FakeSession session;
      session = FakeSession(host.id, (command) {
        if (hanging.contains(host.id)) return session.hang();
        return handler?.call(host.id, command) ?? Future.value(('ok', 0));
      });
      sessions[host.id] = session;
      return session;
    } finally {
      inFlightOpens--;
    }
  }
}

void main() {
  group('RunbookRunService', () {
    test('runs every host and closes every session', () async {
      final factory = FakeFactory();
      final service = RunbookRunService(sessionFactory: factory);
      final results = await service.start(runbook(['a', 'b']), [
        host('h1'),
        host('h2'),
        host('h3'),
      ]).result;

      expect(
        results.map((r) => r.status),
        everyElement(RunHostStatus.succeeded),
      );
      expect(factory.sessions.length, 3);
      for (final s in factory.sessions.values) {
        expect(s.ran, ['a', 'b']);
        expect(s.closes, 1);
      }
    });

    test('a host that cannot connect fails alone and runs no step', () async {
      final factory = FakeFactory(failing: {'h2'});
      final events = <RunEvent>[];
      final results = await RunbookRunService(sessionFactory: factory).start(
        runbook(['a']),
        [host('h1'), host('h2')],
        onEvent: events.add,
      ).result;

      expect(results[0].status, RunHostStatus.succeeded);
      expect(results[1].status, RunHostStatus.failed);
      expect(results[1].connectionError, 'connection refused');
      expect(results[1].execution, isNull);
      expect(
        events.whereType<StepStatusEvent>().where(
          (e) => e.hostId == 'h2' && e.status == RunStepStatus.running,
        ),
        isEmpty,
      );
      expect(
        events.whereType<HostStatusEvent>().any(
          (e) => e.hostId == 'h2' && e.status == RunHostStatus.connecting,
        ),
        isTrue,
      );
    });

    test('a failing step stops that host only', () async {
      final factory = FakeFactory(
        handler: (hostId, command) async =>
            hostId == 'h1' && command == 'a' ? ('boom', 2) : ('ok', 0),
      );
      final results = await RunbookRunService(
        sessionFactory: factory,
      ).start(runbook(['a', 'b']), [host('h1'), host('h2')]).result;

      expect(results[0].status, RunHostStatus.failed);
      expect(results[0].execution!.failedStep!.id, 's0');
      expect(results[0].execution!.stepResults.single.exitCode, 2);
      expect(factory.sessions['h1']!.ran, ['a']);
      expect(results[1].status, RunHostStatus.succeeded);
      expect(factory.sessions['h2']!.ran, ['a', 'b']);
      expect(factory.sessions['h1']!.closes, 1);
    });

    test('never opens more than four connections at once', () async {
      final factory = FakeFactory(openDelay: const Duration(milliseconds: 10));
      final hosts = [for (var i = 0; i < 11; i++) host('h$i')];
      final results = await RunbookRunService(
        sessionFactory: factory,
      ).start(runbook(['a']), hosts).result;

      expect(results, hasLength(11));
      expect(factory.maxInFlightOpens, RunbookRunService.maxConcurrentHosts);
      expect(factory.sessions.values.every((s) => s.closes == 1), isTrue);
    });

    test('cancel interrupts, closes and marks steps cancelled', () async {
      final factory = FakeFactory(hanging: {'h1', 'h2'});
      final events = <RunEvent>[];
      final run = RunbookRunService(sessionFactory: factory).start(
        runbook(['a', 'b']),
        [host('h1'), host('h2')],
        onEvent: events.add,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await run.cancel();
      final results = await run.result.timeout(const Duration(seconds: 2));

      expect(
        results.map((r) => r.status),
        everyElement(RunHostStatus.cancelled),
      );
      for (final s in factory.sessions.values) {
        expect(s.interrupts, 1);
        expect(s.closes, greaterThanOrEqualTo(1));
      }
      final last = <String, RunStepStatus>{
        for (final e in events.whereType<StepStatusEvent>())
          '${e.hostId}/${e.stepId}': e.status,
      };
      expect(last.values, everyElement(RunStepStatus.cancelled));
      expect(last, hasLength(4));
    });

    test(
      'cancel while connecting completes and closes the late session',
      () async {
        final factory = FakeFactory(
          openDelay: const Duration(milliseconds: 50),
        );
        final run = RunbookRunService(
          sessionFactory: factory,
        ).start(runbook(['a']), [host('h1'), host('h2')]);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await run.cancel();
        final results = await run.result.timeout(const Duration(seconds: 2));
        expect(
          results.map((r) => r.status),
          everyElement(RunHostStatus.cancelled),
        );

        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(factory.sessions.values.every((s) => s.closes == 1), isTrue);
        expect(factory.sessions.values.every((s) => s.ran.isEmpty), isTrue);
      },
    );

    test('queued hosts are cancelled without ever connecting', () async {
      final factory = FakeFactory(hanging: {for (var i = 0; i < 4; i++) 'h$i'});
      final run = RunbookRunService(
        sessionFactory: factory,
      ).start(runbook(['a']), [for (var i = 0; i < 6; i++) host('h$i')]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await run.cancel();
      final results = await run.result.timeout(const Duration(seconds: 2));
      expect(results, hasLength(6));
      expect(
        results.map((r) => r.status),
        everyElement(RunHostStatus.cancelled),
      );
      expect(factory.opened, 4);
    });

    test('a session that throws mid-run is still closed', () async {
      final factory = FakeFactory(
        handler: (hostId, command) => throw StateError('dropped'),
      );
      final results = await RunbookRunService(
        sessionFactory: factory,
      ).start(runbook(['a']), [host('h1')]).result;
      expect(results.single.status, RunHostStatus.failed);
      expect(factory.sessions['h1']!.closes, 1);
    });

    test('a snippet runs as a one-step runbook with input variables', () async {
      final factory = FakeFactory(
        handler: (hostId, command) async => ('ran $command', 0),
      );
      final snippet = SnippetModel(
        id: 'sn',
        workspaceId: 'w',
        title: 'Restart',
        code: 'systemctl restart \${INPUT:svc} && echo \${HOME}',
      );
      final results = await RunbookRunService(sessionFactory: factory)
          .start(
            RunbookRunService.runbookForSnippet(snippet),
            [host('h1')],
            variableValues: {'svc': 'nginx'},
          )
          .result;

      expect(results.single.status, RunHostStatus.succeeded);
      expect(factory.sessions['h1']!.ran, [
        'systemctl restart nginx && echo \${HOME}',
      ]);
      expect(results.single.execution!.stepResults, hasLength(1));
    });
  });
}
