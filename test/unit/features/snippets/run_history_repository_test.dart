import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/snippets/data/repositories/run_history_repository.dart';
import 'package:shellvibe/features/snippets/domain/models/active_run.dart';
import 'package:shellvibe/features/snippets/domain/models/run_strategy.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_step_model.dart';
import 'package:shellvibe/features/snippets/domain/services/runbook_executor.dart';
import 'package:shellvibe/features/snippets/domain/services/runbook_run_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/database/daos/run_history_dao.dart';

void main() {
  late AppDatabase db;
  late RunHistoryRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = RunHistoryRepository(db.runHistoryDao);
  });

  tearDown(() => db.close());

  const step1 = RunbookStepModel(
    id: 's1',
    runbookId: 'rb',
    stepOrder: 1,
    command: r'echo ${INPUT:who}',
  );
  const step2 = RunbookStepModel(
    id: 's2',
    runbookId: 'rb',
    stepOrder: 2,
    command: 'uptime',
  );

  RunbookModel runbook({String id = 'rb'}) => RunbookModel(
    id: id,
    workspaceId: 'default',
    title: 'Deploy',
    createdAt: DateTime(2026),
    steps: const [step1, step2],
  );

  RunbookStepResult result(
    RunbookStepModel step, {
    String output = 'out',
    int exitCode = 0,
    bool success = true,
    int attempts = 1,
  }) => RunbookStepResult(
    step: step,
    success: success,
    exitCode: exitCode,
    output: output,
    command: step.command.replaceAll(r'${INPUT:who}', 'world'),
    attempts: attempts,
    durationMs: 12,
    errorMessage: success ? null : 'Exit code $exitCode does not match',
  );

  ActiveRun run({
    RunbookModel? book,
    DateTime? startedAt,
    String output = 'out',
  }) {
    return ActiveRun(
      runbook: book ?? runbook(),
      running: false,
      strategy: RunStrategy.parallel(3),
      variableValues: const {'who': 'world'},
      startedAt: startedAt ?? DateTime(2026, 1, 1, 10),
      finishedAt: (startedAt ?? DateTime(2026, 1, 1, 10)).add(
        const Duration(seconds: 5),
      ),
      hosts: [
        HostRunState(
          hostId: 'h1',
          label: 'web-1',
          status: RunHostStatus.succeeded,
          steps: const {
            's1': RunStepStatus.success,
            's2': RunStepStatus.success,
          },
          results: {
            's1': result(step1, output: output, attempts: 2),
            's2': result(step2),
          },
        ),
        HostRunState(
          hostId: 'h2',
          label: 'web-2',
          status: RunHostStatus.failed,
          error: 'connection refused',
          steps: const {
            's1': RunStepStatus.pending,
            's2': RunStepStatus.pending,
          },
        ),
        HostRunState(
          hostId: 'h3',
          label: 'web-3',
          status: RunHostStatus.skipped,
          steps: const {
            's1': RunStepStatus.skipped,
            's2': RunStepStatus.skipped,
          },
        ),
      ],
    );
  }

  test('a saved run reads back with hosts, steps and snapshots', () async {
    final id = await repo.save(run());
    final stored = (await repo.load(id))!;

    expect(stored.summary.status, 'failed');
    expect(stored.summary.summaryText, '1 of 3 hosts succeeded');
    expect(stored.summary.strategy, RunStrategy.parallel(3));
    expect(stored.hostIds, ['h1', 'h2', 'h3']);
    expect(stored.run.fromHistory, isTrue);
    expect(stored.run.variableValues, {'who': 'world'});
    expect(stored.run.hosts.map((h) => h.status), [
      RunHostStatus.succeeded,
      RunHostStatus.failed,
      RunHostStatus.skipped,
    ]);
    expect(stored.run.hosts[1].error, 'connection refused');

    final r = stored.run.hosts.first.results['s1']!;
    expect(r.output, 'out');
    expect(r.exitCode, 0);
    expect(r.attempts, 2);
    // The command as it was sent, not the template.
    expect(r.command, 'echo world');
    expect(stored.run.runbook.steps.map((s) => s.stepOrder), [1, 2]);
    // A step that never ran still has its status, but no result.
    expect(stored.run.hosts[2].steps['s1'], RunStepStatus.skipped);
    expect(stored.run.hosts[2].results, isEmpty);
  });

  test(
    'the runbook can be edited or deleted and history still renders',
    () async {
      await db.runbooksDao.insertRunbook(RunbooksCompanionHelper.minimal('rb'));
      final id = await repo.save(run());
      await db.runbooksDao.deleteRunbook('rb');
      final stored = await repo.load(id);
      expect(stored, isNotNull);
      expect(stored!.run.runbook.title, 'Deploy');
    },
  );

  test('a snippet run is stored without a runbook id', () async {
    final snippetBook = runbook(id: 'snippet:sn');
    final id = await repo.save(run(book: snippetBook));
    final summary = (await repo.forSnippets()).single;
    expect(summary.id, id);
    expect(summary.kind, 'snippet');
    expect(summary.runbookId, isNull);
  });

  test('output is cut to its last 16 KiB and marked truncated', () async {
    final big = '${'a' * 20000}END';
    final id = await repo.save(run(output: big));
    final r = (await repo.load(id))!.run.hosts.first.results['s1']!;
    expect(utf8.encode(r.output).length, RunHistoryRepository.maxOutputBytes);
    expect(r.output.endsWith('END'), isTrue);
    expect(r.outputTruncated, isTrue);

    final small = (await repo.load(
      await repo.save(run()),
    ))!.run.hosts.first.results['s1']!;
    expect(small.outputTruncated, isFalse);
  });

  test('keeps the last 20 runs of a runbook and prunes older ones', () async {
    final ids = <String>[];
    for (var i = 0; i < 23; i++) {
      ids.add(
        await repo.save(
          run(startedAt: DateTime(2026, 1, 1).add(Duration(minutes: i))),
        ),
      );
    }
    final kept = await repo.forRunbook('rb');
    expect(kept, hasLength(RunHistoryDao.runbookRetention));
    // Newest first; the three oldest are gone.
    expect(kept.first.id, ids.last);
    expect(await repo.load(ids.first), isNull);
    expect(await repo.load(ids[2]), isNull);
    expect(await repo.load(ids[3]), isNotNull);

    // Another runbook's history is separate.
    await repo.save(run(book: runbook(id: 'other')));
    expect(await repo.forRunbook('other'), hasLength(1));
    expect(await repo.forRunbook('rb'), hasLength(20));
  });

  test('keeps the last 50 snippet runs overall', () async {
    for (var i = 0; i < 52; i++) {
      await repo.save(
        run(
          book: runbook(id: 'snippet:s${i % 3}'),
          startedAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
        ),
      );
    }
    expect(await repo.forSnippets(), hasLength(50));
  });

  test('deleting a run cascades to its hosts and steps', () async {
    final id = await repo.save(run());
    await repo.clear(runbookId: 'rb');
    expect(await repo.load(id), isNull);
    for (final table in ['runbook_run_hosts', 'runbook_run_steps']) {
      final rows = await db.customSelect('SELECT 1 FROM $table').get();
      expect(rows, isEmpty, reason: table);
    }
  });

  test('clearing snippet history leaves runbook history alone', () async {
    await repo.save(run());
    await repo.save(run(book: runbook(id: 'snippet:sn')));
    await repo.clear();
    expect(await repo.forSnippets(), isEmpty);
    expect(await repo.forRunbook('rb'), hasLength(1));
  });

  test('latestByRunbook returns the newest run per runbook', () async {
    await repo.save(run(startedAt: DateTime(2026, 1, 1)));
    final newest = await repo.save(run(startedAt: DateTime(2026, 2, 1)));
    final latest = await repo.latestByRunbook(['rb', 'none']);
    expect(latest.keys, ['rb']);
    expect(latest['rb']!.id, newest);
  });
}

/// A minimal runbook row, for the "deleted later" case.
class RunbooksCompanionHelper {
  static RunbooksCompanion minimal(String id) => RunbooksCompanion.insert(
    id: id,
    workspaceId: 'default',
    title: 'Deploy',
    createdAt: DateTime(2026),
  );
}
