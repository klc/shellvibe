import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/snippets/data/run_providers.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_step_model.dart';
import 'package:shellvibe/features/snippets/domain/models/snippet_model.dart';
import 'package:shellvibe/features/snippets/domain/models/variable_declaration.dart';
import 'package:shellvibe/features/snippets/domain/services/remote_command_session.dart';
import 'package:shellvibe/features/snippets/domain/services/runbook_run_service.dart';
import 'package:shellvibe/features/snippets/presentation/notifiers/runbook_run_notifier.dart';
import 'package:shellvibe/features/snippets/presentation/notifiers/snippets_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

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

class _EchoSession implements RemoteCommandSession {
  @override
  Future<(String, int)> run(String command, Duration timeout) async =>
      ('ran $command', 0);

  @override
  Future<void> interrupt() async {}

  @override
  Future<void> close() async {}
}

class _EchoFactory implements RemoteCommandSessionFactory {
  @override
  Future<RemoteCommandSession> open(HostModel host) async => _EchoSession();
}

class _FakeSnippets extends SnippetsNotifier {
  _FakeSnippets(this.list);
  final List<SnippetModel> list;

  @override
  Future<List<SnippetModel>> build() async => list;
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
        snippetsProvider.overrideWith(() => _FakeSnippets(const [])),
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
          snippetsProvider.overrideWith(() => _FakeSnippets(const [])),
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

  test('a secret declared on a snippet step is masked in the result', () async {
    const snippet = SnippetModel(
      id: 'sn',
      workspaceId: 'w',
      title: 'sn',
      code: 'login \${INPUT:TOKEN}',
      variables: [
        VariableDeclaration(name: 'TOKEN', type: VariableType.secret),
      ],
    );
    final snippetRunbook = RunbookModel(
      id: 'rb2',
      workspaceId: 'w',
      title: 'rb2',
      createdAt: DateTime(2026),
      steps: const [
        RunbookStepModel(
          id: 's1',
          runbookId: 'rb2',
          stepOrder: 1,
          command: '',
          kind: StepKind.snippet,
          snippetId: 'sn',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        snippetsProvider.overrideWith(() => _FakeSnippets([snippet])),
        runbookRunServiceProvider.overrideWithValue(
          RunbookRunService(
            sessionFactory: _EchoFactory(),
            lookupSnippet: (_) async => snippet.code,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(runbookRunProvider.notifier)
        .start(snippetRunbook, [host], variableValues: {'TOKEN': 'hunter2'});

    final result = container.read(runbookRunProvider)!.hosts.single.results;
    expect(result, isNotEmpty);
    for (final r in result.values) {
      expect(r.command, isNot(contains('hunter2')));
      expect(r.output, isNot(contains('hunter2')));
    }
  });

  group('history', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.workspacesDao.insertWorkspace(
        WorkspacesCompanion.insert(
          id: 'w',
          name: 'w',
          createdAt: DateTime(2026),
        ),
      );
    });

    tearDown(() => db.close());

    ProviderContainer withDb(_Factory factory) {
      final container = ProviderContainer(
        overrides: [
          remoteCommandSessionFactoryProvider.overrideWithValue(factory),
          snippetsProvider.overrideWith(() => _FakeSnippets(const [])),
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a cancelled run is recorded once it settles', () async {
      final factory = _Factory();
      final container = withDb(factory);
      final notifier = container.read(runbookRunProvider.notifier);

      final done = notifier.start(runbook, [host]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Nothing is written while the run is in flight.
      expect(
        await container.read(runHistoryRepositoryProvider).forRunbook('rb'),
        isEmpty,
      );

      await notifier.cancel();
      await done.timeout(const Duration(seconds: 2));

      final runs = await container
          .read(runHistoryRepositoryProvider)
          .forRunbook('rb');
      expect(runs, hasLength(1));
      expect(runs.single.status, 'cancelled');
    });

    test('a history failure does not fail the run', () async {
      // No database override: saving throws, the run still completes.
      final factory = _Factory();
      final container = containerWith(factory);
      final notifier = container.read(runbookRunProvider.notifier);
      final done = notifier.start(runbook, [host]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await notifier.cancel();
      await done.timeout(const Duration(seconds: 2));
      expect(container.read(runbookRunProvider)!.running, isFalse);
    });
  });
}
