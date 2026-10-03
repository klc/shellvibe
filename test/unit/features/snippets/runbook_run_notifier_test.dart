import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/snippets/data/run_providers.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_step_model.dart';
import 'package:shellvibe/features/snippets/domain/services/remote_command_session.dart';
import 'package:shellvibe/features/snippets/domain/services/runbook_run_service.dart';
import 'package:shellvibe/features/snippets/presentation/notifiers/runbook_run_notifier.dart';

/// A session whose command only ends when interrupted.
class _HangingSession implements RemoteCommandSession {
  final _interrupted = Completer<void>();
  int interrupts = 0;
  int closes = 0;

  @override
  Future<(String, int)> run(String command, Duration timeout) async {
    await _interrupted.future;
    return ('', 130);
  }

  @override
  Future<void> interrupt() async {
    interrupts++;
    if (!_interrupted.isCompleted) _interrupted.complete();
  }

  @override
  Future<void> close() async => closes++;
}

class _Factory implements RemoteCommandSessionFactory {
  final sessions = <_HangingSession>[];

  @override
  Future<RemoteCommandSession> open(HostModel host) async {
    final session = _HangingSession();
    sessions.add(session);
    return session;
  }
}

void main() {
  final host = HostModel(
    id: 'h1',
    workspaceId: 'w',
    label: 'web-1',
    hostname: 'web-1',
    createdAt: DateTime(2026),
  );
  final runbook = RunbookModel(
    id: 'rb',
    workspaceId: 'w',
    title: 'rb',
    createdAt: DateTime(2026),
    steps: const [
      RunbookStepModel(id: 's1', runbookId: 'rb', stepOrder: 1, command: 'x'),
    ],
  );

  ProviderContainer containerWith(_Factory factory) {
    final container = ProviderContainer(
      overrides: [
        remoteCommandSessionFactoryProvider.overrideWithValue(factory),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('cancel stops a running run and records cancelled state', () async {
    final factory = _Factory();
    final container = containerWith(factory);
    final notifier = container.read(runbookRunProvider.notifier);

    final done = notifier.start(runbook, [host]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(runbookRunProvider)!.running, isTrue);

    await notifier.cancel();
    await done.timeout(const Duration(seconds: 2));

    final run = container.read(runbookRunProvider)!;
    expect(run.running, isFalse);
    expect(run.hosts.single.status, RunHostStatus.cancelled);
    expect(run.hosts.single.steps['s1'], RunStepStatus.cancelled);
    expect(factory.sessions.single.interrupts, 1);
    expect(factory.sessions.single.closes, greaterThanOrEqualTo(1));
  });

  test(
    'disposing the container mid-run interrupts and closes sessions',
    () async {
      final factory = _Factory();
      final container = ProviderContainer(
        overrides: [
          remoteCommandSessionFactoryProvider.overrideWithValue(factory),
        ],
      );
      final notifier = container.read(runbookRunProvider.notifier);

      unawaited(notifier.start(runbook, [host]));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(factory.sessions.single.interrupts, 1);
      expect(factory.sessions.single.closes, greaterThanOrEqualTo(1));
    },
  );
}
