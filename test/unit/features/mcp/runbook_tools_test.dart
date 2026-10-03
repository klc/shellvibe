import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/data/repositories/hosts_repository.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_audit_repository.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_grant_repository.dart';
import 'package:shellvibe/features/mcp/data/tools/mcp_tool_handler.dart';
import 'package:shellvibe/features/mcp/data/tools/runbook_tools.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_models.dart';
import 'package:shellvibe/features/mcp/domain/services/approval_coordinator.dart';
import 'package:shellvibe/features/mcp/domain/services/output_redactor.dart';
import 'package:shellvibe/features/snippets/data/repositories/run_history_repository.dart';
import 'package:shellvibe/features/snippets/data/repositories/runbooks_repository.dart';
import 'package:shellvibe/features/snippets/data/repositories/snippets_repository.dart';
import 'package:shellvibe/features/snippets/domain/models/active_run.dart';
import 'package:shellvibe/features/snippets/domain/models/run_strategy.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_model.dart';
import 'package:shellvibe/features/snippets/domain/models/runbook_step_model.dart';
import 'package:shellvibe/features/snippets/domain/services/runbook_executor.dart';
import 'package:shellvibe/features/snippets/domain/services/runbook_run_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';

class FakeGateway implements RunbookRunGateway {
  @override
  ActiveRun? current;
  @override
  bool isRunning = false;

  final started =
      <
        ({
          RunbookModel runbook,
          List<String> hostIds,
          Map<String, String> values,
          RunStrategy strategy,
          RunTrigger trigger,
          String runId,
        })
      >[];
  Completer<void> done = Completer<void>();
  int cancels = 0;

  @override
  Future<void> start(
    RunbookModel runbook,
    List<HostModel> hosts, {
    required Map<String, String> variableValues,
    required RunStrategy strategy,
    required RunTrigger triggeredBy,
    required String runId,
  }) {
    started.add((
      runbook: runbook,
      hostIds: [for (final h in hosts) h.id],
      values: variableValues,
      strategy: strategy,
      trigger: triggeredBy,
      runId: runId,
    ));
    isRunning = true;
    current = ActiveRun(
      id: runId,
      triggeredBy: triggeredBy,
      runbook: runbook,
      running: true,
      strategy: strategy,
      startedAt: DateTime.now(),
      hosts: [
        for (final h in hosts) HostRunState(hostId: h.id, label: h.label),
      ],
    );
    return done.future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    isRunning = false;
    current = current?.copyWith(running: false, finishedAt: DateTime.now());
  }
}

const _ctx = McpToolContext(
  clientId: 'client-1',
  clientName: 'Claude Code',
  workspaceId: 'ws',
  connectionScopeId: 'scope',
);
const _other = McpToolContext(
  clientId: 'client-2',
  clientName: 'Other Agent',
  workspaceId: 'ws',
  connectionScopeId: 'scope2',
);

void main() {
  late AppDatabase db;
  late FakeGateway gateway;
  late ApprovalCoordinator coordinator;
  late McpGrantRepository grants;
  late McpAuditRepository audit;
  late RunbookRunTracker tracker;
  late RunHistoryRepository history;
  late ListRunbooksTool list;
  late RunRunbookTool run;
  late GetRunbookRunTool get;
  late CancelRunbookRunTool cancel;

  Future<void> host(
    String id, {
    String workspace = 'ws',
    bool visible = true,
    String environment = 'dev',
    bool granted = true,
  }) async {
    await db.hostsDao.insertHost(
      HostsCompanion.insert(
        id: id,
        workspaceId: workspace,
        label: 'label-$id',
        hostname: '$id.example.test',
        createdAt: DateTime(2026),
        mcpVisible: Value(visible),
        environment: Value(environment),
      ),
    );
    if (granted) {
      await grants.grant(
        clientId: 'client-1',
        hostId: id,
        mode: McpAccessMode.guarded,
      );
    }
  }

  Future<void> runbook({
    String id = 'rb',
    String workspace = 'ws',
    String title = 'Release',
    String? tags,
    String? variables,
    String? defaultHostIds,
    List<RunbookStepsCompanion>? steps,
  }) async {
    await db.runbooksDao.insertRunbook(
      RunbooksCompanion.insert(
        id: id,
        workspaceId: workspace,
        title: title,
        description: const Value('Ships the thing'),
        createdAt: DateTime(2026),
        tags: Value(tags),
        variables: Value(variables),
        defaultHostIds: Value(defaultHostIds),
      ),
    );
    await db.runbooksDao.replaceSteps(
      id,
      steps ??
          [
            RunbookStepsCompanion.insert(
              id: '$id-1',
              runbookId: id,
              stepOrder: 1,
              command: 'systemctl restart api',
            ),
          ],
    );
  }

  /// Answers the next runbook approval the way a user would.
  Future<RunbookApprovalRequest> answer(
    RunbookApprovalDecision decision,
  ) async {
    for (var i = 0; i < 100; i++) {
      final pending = coordinator.currentRunbooks;
      if (pending.isNotEmpty) {
        coordinator.resolveRunbook(pending.single.id, decision);
        return pending.single.request;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('no approval was requested');
  }

  Future<List<Map<String, Object?>>> auditRows() async {
    final rows = await audit.query();
    return [
      for (final r in rows)
        {
          'tool': r.tool,
          'decision': r.decision,
          'args': jsonDecode(r.argsJson),
          'hostLabel': r.hostLabel,
        },
    ];
  }

  Matcher toolError(McpErrorCode code, [Object? message]) => throwsA(
    isA<McpToolException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.message, 'message', message ?? isNotEmpty),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'ws',
        name: 'Work',
        createdAt: DateTime(2026),
      ),
    );
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'other-ws',
        name: 'Other',
        createdAt: DateTime(2026),
      ),
    );
    for (final id in ['client-1', 'client-2']) {
      await db.mcpDao.insertClient(
        McpClientsCompanion.insert(
          id: id,
          workspaceId: 'ws',
          name: id,
          tokenHash: 'hash-$id',
          createdAt: DateTime(2026),
        ),
      );
    }
    gateway = FakeGateway();
    coordinator = ApprovalCoordinator();
    grants = McpGrantRepository(db.mcpDao);
    audit = McpAuditRepository(db.mcpDao);
    tracker = RunbookRunTracker();
    history = RunHistoryRepository(db.runHistoryDao);
    final runbooksRepo = RunbooksRepository(db.runbooksDao);
    final snippetsRepo = SnippetsRepository(db.snippetsDao);
    final hostsRepo = HostsRepository(hostsDao: db.hostsDao);
    const redactor = OutputRedactor();
    list = ListRunbooksTool(
      runbooksRepository: runbooksRepo,
      snippetsRepository: snippetsRepo,
      hostsDao: db.hostsDao,
      redactor: redactor,
    );
    run = RunRunbookTool(
      runbooksRepository: runbooksRepo,
      snippetsRepository: snippetsRepo,
      hostsRepository: hostsRepo,
      hostsDao: db.hostsDao,
      grantRepository: grants,
      auditRepository: audit,
      approvalCoordinator: coordinator,
      gateway: gateway,
      tracker: tracker,
      redactor: redactor,
    );
    get = GetRunbookRunTool(
      gateway: gateway,
      tracker: tracker,
      historyRepository: history,
      redactor: redactor,
    );
    cancel = CancelRunbookRunTool(
      gateway: gateway,
      tracker: tracker,
      auditRepository: audit,
      redactor: redactor,
    );
  });

  tearDown(() async {
    coordinator.dispose();
    await db.close();
  });

  group('list_runbooks', () {
    test('describes steps, policy, variables and default hosts', () async {
      await db.snippetsDao.insertSnippet(
        SnippetsCompanion.insert(
          id: 'sn',
          workspaceId: 'ws',
          title: 'Disk usage',
          code: 'df -h',
        ),
      );
      await host('visible');
      await host('hidden', visible: false);
      await host('foreign', workspace: 'other-ws');
      await runbook(
        tags: '["ops"]',
        defaultHostIds: '["visible","hidden","foreign","gone"]',
        variables:
            '[{"name":"env","type":"enum","options":["staging","prod"],'
            '"defaultValue":"staging","description":"Where"},'
            '{"name":"token","type":"secret","defaultValue":"leak"}]',
        steps: [
          RunbookStepsCompanion.insert(
            id: 's1',
            runbookId: 'rb',
            stepOrder: 1,
            command: r'deploy ${INPUT:env} --token ${INPUT:token}',
            retries: const Value(2),
            onFailure: const Value('continue'),
            expectedOutputPattern: const Value('ok'),
          ),
          RunbookStepsCompanion.insert(
            id: 's2',
            runbookId: 'rb',
            stepOrder: 2,
            command: '# snippet: Disk usage',
            kind: const Value('snippet'),
            snippetId: const Value('sn'),
          ),
          RunbookStepsCompanion.insert(
            id: 's3',
            runbookId: 'rb',
            stepOrder: 3,
            command: 'Check the dashboards',
            kind: const Value('approval'),
          ),
        ],
      );

      final result = await list.execute(_ctx, const {}) as Map<String, Object?>;
      final rb = (result['runbooks'] as List).single as Map<String, Object?>;

      expect(rb['id'], 'rb');
      expect(rb['title'], 'Release');
      expect(rb['description'], 'Ships the thing');
      expect(rb['tags'], ['ops']);
      final steps = (rb['steps'] as List).cast<Map<String, Object?>>();
      expect(steps[0]['kind'], 'command');
      expect(steps[0]['command'], contains('deploy'));
      expect(steps[0]['retries'], 2);
      expect(steps[0]['onFailure'], 'continue');
      expect(steps[0]['expectedOutput'], 'ok');
      expect(steps[1]['kind'], 'snippet');
      expect(steps[1]['snippet'], 'Disk usage');
      expect(steps[1].containsKey('command'), isFalse);
      expect(steps[2]['kind'], 'approval');
      expect(steps[2]['message'], 'Check the dashboards');
      expect(steps[2].containsKey('retries'), isFalse);

      // Only hosts this client may see.
      expect(rb['defaultHostIds'], ['visible']);

      final vars = (rb['variables'] as List).cast<Map<String, Object?>>();
      final env = vars.firstWhere((v) => v['name'] == 'env');
      expect(env['type'], 'enum');
      expect(env['options'], ['staging', 'prod']);
      expect(env['defaultValue'], 'staging');
      expect(env['description'], 'Where');
      final token = vars.firstWhere((v) => v['name'] == 'token');
      expect(token['type'], 'secret');
      expect(token['required'], isTrue);
      expect(token.containsKey('defaultValue'), isFalse);
      expect(jsonEncode(result), isNot(contains('leak')));
    });

    test('a literal secret in a command is masked', () async {
      await runbook(
        steps: [
          RunbookStepsCompanion.insert(
            id: 's1',
            runbookId: 'rb',
            stepOrder: 1,
            command: 'curl -H "Authorization: token=AKIAABCDEFGHIJKLMNOP" x',
          ),
        ],
      );
      final result = await list.execute(_ctx, const {}) as Map<String, Object?>;
      expect(jsonEncode(result), isNot(contains('AKIAABCDEFGHIJKLMNOP')));
    });

    test('only this workspace, filtered by tag and query', () async {
      await runbook(id: 'a', title: 'Deploy API', tags: '["ops"]');
      await runbook(id: 'b', title: 'Rotate logs', tags: '["ops","logs"]');
      await runbook(id: 'c', title: 'Elsewhere', workspace: 'other-ws');

      Future<List<Object?>> ids(Map<String, Object?> args) async {
        final r = await list.execute(_ctx, args) as Map<String, Object?>;
        return [for (final x in r['runbooks'] as List) (x as Map)['id']];
      }

      expect(await ids(const {}), ['a', 'b']);
      expect(await ids(const {'tag': 'logs'}), ['b']);
      expect(await ids(const {'query': 'DEPLOY'}), ['a']);
      expect(await ids(const {'query': 'restart api'}), ['a', 'b']);
    });
  });

  group('run_runbook validation', () {
    test('an unknown runbook, and one in another workspace', () async {
      await runbook(id: 'foreign', workspace: 'other-ws');
      await host('h1');
      for (final id in ['nope', 'foreign']) {
        await expectLater(
          run.execute(_ctx, {
            'runbookId': id,
            'hostIds': ['h1'],
          }),
          toolError(McpErrorCode.runbookNotFound),
        );
      }
      expect(coordinator.currentRunbooks, isEmpty);
      expect(gateway.started, isEmpty);
    });

    test(
      'a hidden host, a foreign host and a missing host look the same',
      () async {
        await runbook();
        await host('hidden', visible: false);
        await host('foreign', workspace: 'other-ws');
        for (final id in ['hidden', 'foreign', 'missing']) {
          await expectLater(
            run.execute(_ctx, {
              'runbookId': 'rb',
              'hostIds': [id],
            }),
            toolError(McpErrorCode.hostNotVisible),
          );
        }
      },
    );

    test('a host without a grant points at request_host_access', () async {
      await runbook();
      await host('h1', granted: false);
      await expectLater(
        run.execute(_ctx, {
          'runbookId': 'rb',
          'hostIds': ['h1'],
        }),
        toolError(
          McpErrorCode.hostAccessRequired,
          contains('request_host_access'),
        ),
      );
      expect(coordinator.currentRunbooks, isEmpty);
    });

    test('one inaccessible host among several refuses the whole run', () async {
      await runbook();
      await host('h1');
      await host('h2', granted: false);
      await expectLater(
        run.execute(_ctx, {
          'runbookId': 'rb',
          'hostIds': ['h1', 'h2'],
        }),
        toolError(McpErrorCode.hostAccessRequired),
      );
      expect(gateway.started, isEmpty);
    });

    test('missing required variables are listed before any dialog', () async {
      await host('h1');
      await runbook(
        variables: '[{"name":"env"},{"name":"region"}]',
        steps: [
          RunbookStepsCompanion.insert(
            id: 's1',
            runbookId: 'rb',
            stepOrder: 1,
            command: r'go ${INPUT:env} ${INPUT:region} ${INPUT:tag}',
          ),
        ],
      );
      await expectLater(
        run.execute(_ctx, {
          'runbookId': 'rb',
          'hostIds': ['h1'],
          'variables': {'tag': 'v1'},
        }),
        toolError(McpErrorCode.invalidVariables, contains('env, region')),
      );
      expect(coordinator.currentRunbooks, isEmpty);
      expect(gateway.started, isEmpty);
    });

    test('a secret variable cannot be passed', () async {
      await host('h1');
      await runbook(
        variables: '[{"name":"token","type":"secret"}]',
        steps: [
          RunbookStepsCompanion.insert(
            id: 's1',
            runbookId: 'rb',
            stepOrder: 1,
            command: r'login ${INPUT:token}',
          ),
        ],
      );
      await expectLater(
        run.execute(_ctx, {
          'runbookId': 'rb',
          'hostIds': ['h1'],
          'variables': {'token': 'hunter2'},
        }),
        toolError(McpErrorCode.invalidVariables, contains('secret')),
      );
      expect(coordinator.currentRunbooks, isEmpty);
      // The rejected value is not in the audit log either.
      expect(jsonEncode(await auditRows()), isNot(contains('hunter2')));
    });

    test(
      'unknown names, a bad choice and non-string values are refused',
      () async {
        await host('h1');
        await runbook(
          variables: '[{"name":"env","type":"enum","options":["a","b"]}]',
          steps: [
            RunbookStepsCompanion.insert(
              id: 's1',
              runbookId: 'rb',
              stepOrder: 1,
              command: r'go ${INPUT:env}',
            ),
          ],
        );
        Future<Object?> call(Object variables) => run.execute(_ctx, {
          'runbookId': 'rb',
          'hostIds': ['h1'],
          'variables': variables,
        });
        await expectLater(
          call({'env': 'a', 'extra': 'x'}),
          toolError(McpErrorCode.invalidVariables, contains('extra')),
        );
        await expectLater(
          call({'env': 'c'}),
          toolError(McpErrorCode.invalidVariables, contains('one of a, b')),
        );
        await expectLater(
          call({'env': 3}),
          toolError(McpErrorCode.invalidVariables, contains('string')),
        );
        await expectLater(
          call('nope'),
          toolError(McpErrorCode.invalidVariables),
        );
      },
    );

    test('a bad strategy or concurrency is refused', () async {
      await host('h1');
      await runbook();
      await expectLater(
        run.execute(_ctx, {
          'runbookId': 'rb',
          'hostIds': ['h1'],
          'strategy': 'wild',
        }),
        toolError(McpErrorCode.internal, contains('strategy')),
      );
      await expectLater(
        run.execute(_ctx, {
          'runbookId': 'rb',
          'hostIds': ['h1'],
          'concurrency': 99,
        }),
        toolError(McpErrorCode.internal, contains('concurrency')),
      );
    });

    test('while a run is in progress it is busy, before any dialog', () async {
      await host('h1');
      await runbook();
      gateway.isRunning = true;
      await expectLater(
        run.execute(_ctx, {
          'runbookId': 'rb',
          'hostIds': ['h1'],
        }),
        toolError(McpErrorCode.runbookBusy),
      );
      expect(coordinator.currentRunbooks, isEmpty);
      expect(gateway.started, isEmpty);
    });

    test('every refusal is in the audit log with its reason', () async {
      await expectLater(
        run.execute(_ctx, {
          'runbookId': 'nope',
          'hostIds': ['h1'],
        }),
        toolError(McpErrorCode.runbookNotFound),
      );
      final rows = await auditRows();
      expect(rows.single['tool'], 'run_runbook');
      expect(rows.single['decision'], 'denied');
      expect((rows.single['args']! as Map)['rejected'], contains('nope'));
    });
  });

  group('run_runbook approval', () {
    Future<void> seed() async {
      await host('h1', environment: 'prod');
      await host('h2');
      await db.snippetsDao.insertSnippet(
        SnippetsCompanion.insert(
          id: 'sn',
          workspaceId: 'ws',
          title: 'Disk usage',
          code: 'df -h',
        ),
      );
      await runbook(
        variables:
            '[{"name":"env","type":"enum","options":["staging","prod"],'
            '"defaultValue":"staging"},'
            '{"name":"token","type":"secret"}]',
        steps: [
          RunbookStepsCompanion.insert(
            id: 's1',
            runbookId: 'rb',
            stepOrder: 1,
            command: r'deploy ${INPUT:env} ${INPUT:token}',
          ),
          RunbookStepsCompanion.insert(
            id: 's2',
            runbookId: 'rb',
            stepOrder: 2,
            command: '# snippet: Disk usage',
            kind: const Value('snippet'),
            snippetId: const Value('sn'),
          ),
          RunbookStepsCompanion.insert(
            id: 's3',
            runbookId: 'rb',
            stepOrder: 3,
            command: 'Check the dashboards',
            kind: const Value('approval'),
          ),
        ],
      );
    }

    test('the dialog is always asked, and shows what will happen', () async {
      await seed();
      final future = run.execute(_ctx, {
        'runbookId': 'rb',
        'hostIds': ['h1', 'h2'],
        'variables': {'env': 'prod'},
        'strategy': 'rolling',
      });
      final request = await answer(RunbookApprovalDecision.denied);
      await expectLater(future, toolError(McpErrorCode.policyDenied));

      expect(request.clientName, 'Claude Code');
      expect(request.runbookTitle, 'Release');
      expect(request.strategyLabel, 'rolling');
      expect(request.hosts.map((h) => (h.label, h.environment)), [
        ('label-h1', HostEnvironment.prod),
        ('label-h2', HostEnvironment.dev),
      ]);
      expect(request.steps.map((s) => s.kind), [
        'command',
        'snippet',
        'approval',
      ]);
      // A snippet step shows the code that will run.
      expect(request.steps[1].text, 'df -h');
      expect(request.variables, {'env': 'prod'});
      expect(request.secretFields.map((f) => f.name), ['token']);
    });

    test('denied: no run, and a refusal in the log', () async {
      await seed();
      final future = run.execute(_ctx, {
        'runbookId': 'rb',
        'hostIds': ['h2'],
      });
      await answer(RunbookApprovalDecision.denied);
      await expectLater(
        future,
        toolError(McpErrorCode.policyDenied, contains('declined')),
      );

      expect(gateway.started, isEmpty);
      final rows = await auditRows();
      expect(rows.single['decision'], 'denied');
    });

    test('approved: starts with the merged values, the dialog\'s secrets '
        'included, and returns at once', () async {
      await seed();
      final future = run.execute(_ctx, {
        'runbookId': 'rb',
        'hostIds': ['h1', 'h2'],
        'variables': {'env': 'prod'},
        'strategy': 'parallel',
        'concurrency': 2,
      });
      await answer(
        const RunbookApprovalDecision(
          approved: true,
          secretValues: {'token': 'hunter2'},
        ),
      );
      final result = await future as Map<String, Object?>;

      final started = gateway.started.single;
      expect(started.runbook.id, 'rb');
      expect(started.hostIds, ['h1', 'h2']);
      expect(started.values, {'env': 'prod', 'token': 'hunter2'});
      expect(started.strategy, RunStrategy.parallel(2));
      expect(started.trigger.clientId, 'client-1');
      expect(started.trigger.clientName, 'Claude Code');

      // It did not wait for the run: the gateway's run is still going.
      expect(gateway.done.isCompleted, isFalse);
      expect(result['runId'], started.runId);
      expect(result['status'], 'running');
      expect(result['note'], contains('get_runbook_run'));
      expect(jsonEncode(result), isNot(contains('hunter2')));
    });

    test('a variable with a default may be left out', () async {
      await seed();
      final future = run.execute(_ctx, {
        'runbookId': 'rb',
        'hostIds': ['h2'],
      });
      final request = await answer(
        const RunbookApprovalDecision(
          approved: true,
          secretValues: {'token': 'x'},
        ),
      );
      await future;
      expect(request.variables, {'env': 'staging'});
      expect(gateway.started.single.values['env'], 'staging');
    });

    test(
      'the log has names, never values, and the outcome when the run ends',
      () async {
        await seed();
        final future = run.execute(_ctx, {
          'runbookId': 'rb',
          'hostIds': ['h2'],
          'variables': {'env': 'prod'},
        });
        await answer(
          const RunbookApprovalDecision(
            approved: true,
            secretValues: {'token': 'hunter2'},
          ),
        );
        await future;

        var rows = await auditRows();
        expect(rows, hasLength(1));
        expect(rows.single['decision'], 'confirmed');
        final args = rows.single['args']! as Map;
        expect(args['runbookId'], 'rb');
        expect(args['hostIds'], ['h2']);
        expect(args['variables'], containsAll(['env', 'token']));
        expect(jsonEncode(rows), isNot(contains('hunter2')));
        expect(jsonEncode(rows), isNot(contains('"prod"')));

        // The run settles.
        gateway.isRunning = false;
        gateway.current = gateway.current!.copyWith(
          running: false,
          finishedAt: DateTime.now(),
          hosts: [
            HostRunState(
              hostId: 'h2',
              label: 'label-h2',
              status: RunHostStatus.failed,
            ),
          ],
        );
        gateway.done.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        rows = await auditRows();
        expect(rows, hasLength(2));
        final outcome = rows.firstWhere(
          (r) => (r['args']! as Map).containsKey('outcome'),
        );
        expect((outcome['args']! as Map)['outcome'], 'failed');
        expect(outcome['decision'], 'error');
      },
    );

    test('a run that began while the user was deciding is busy', () async {
      await seed();
      final future = run.execute(_ctx, {
        'runbookId': 'rb',
        'hostIds': ['h2'],
      });
      final expectation = expectLater(
        future,
        toolError(McpErrorCode.runbookBusy),
      );
      while (coordinator.currentRunbooks.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      gateway.isRunning = true;
      await answer(
        const RunbookApprovalDecision(
          approved: true,
          secretValues: {'token': 'x'},
        ),
      );
      await expectation;
      expect(gateway.started, isEmpty);
    });

    test('an unanswered approval refuses (fail-closed)', () async {
      await seed();
      final future = run.execute(_ctx, {
        'runbookId': 'rb',
        'hostIds': ['h2'],
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      coordinator.cancelAll();
      await expectLater(future, toolError(McpErrorCode.policyDenied));
      expect(gateway.started, isEmpty);
    });
  });

  group('get_runbook_run', () {
    RunbookModel book() => RunbookModel(
      id: 'rb',
      workspaceId: 'ws',
      title: 'Release',
      createdAt: DateTime(2026),
      steps: const [
        RunbookStepModel(id: 's1', runbookId: 'rb', stepOrder: 1, command: 'a'),
        RunbookStepModel(
          id: 's2',
          runbookId: 'rb',
          stepOrder: 2,
          command: 'Check the dashboards',
          kind: StepKind.approval,
        ),
      ],
    );

    ActiveRun live({
      required bool running,
      List<HostRunState>? hosts,
      String id = 'run-1',
      String clientId = 'client-1',
    }) => ActiveRun(
      id: id,
      triggeredBy: RunTrigger(clientId: clientId, clientName: 'Claude Code'),
      runbook: book(),
      running: running,
      startedAt: DateTime(2026),
      finishedAt: running ? null : DateTime(2026),
      hosts:
          hosts ??
          [
            HostRunState(
              hostId: 'h1',
              label: 'web-1',
              status: RunHostStatus.running,
            ),
          ],
    );

    void track({String id = 'run-1', String clientId = 'client-1'}) {
      tracker.track(
        TrackedRun(runId: id, clientId: clientId, done: gateway.done.future),
      );
    }

    HostRunState host1(
      RunHostStatus status, {
      Map<String, RunStepStatus> steps = const {},
      Map<String, RunbookStepResult> results = const {},
      String? error,
    }) => HostRunState(
      hostId: 'h1',
      label: 'web-1',
      status: status,
      steps: steps,
      results: results,
      error: error,
    );

    test('reports running, then each settled state', () async {
      track();
      gateway.current = live(running: true);
      var r =
          await get.execute(_ctx, {'runId': 'run-1'}) as Map<String, Object?>;
      expect(r['status'], 'running');

      for (final (host, expected) in [
        (host1(RunHostStatus.succeeded), 'succeeded'),
        (host1(RunHostStatus.failed), 'failed'),
        (host1(RunHostStatus.cancelled), 'cancelled'),
      ]) {
        gateway.current = live(running: false, hosts: [host]);
        r = await get.execute(_ctx, {'runId': 'run-1'}) as Map<String, Object?>;
        expect(r['status'], expected, reason: expected);
      }
    });

    test(
      'a run at an approval gate says so, and that MCP cannot continue it',
      () async {
        track();
        gateway.current = live(
          running: true,
          hosts: [
            host1(
              RunHostStatus.running,
              steps: {'s1': RunStepStatus.success, 's2': RunStepStatus.waiting},
            ),
          ],
        );
        final r =
            await get.execute(_ctx, {'runId': 'run-1'}) as Map<String, Object?>;
        expect(r['status'], 'waiting_for_approval');
        expect(r['waitingFor'], {'step': 2, 'message': 'Check the dashboards'});
        expect(r['note'], contains('press Continue'));
      },
    );

    test(
      'per-host and per-step detail: status, exit code, attempts, output',
      () async {
        track();
        const step1 = RunbookStepModel(
          id: 's1',
          runbookId: 'rb',
          stepOrder: 1,
          command: 'a',
        );
        gateway.current = live(
          running: false,
          hosts: [
            host1(
              RunHostStatus.failed,
              steps: {'s1': RunStepStatus.failed, 's2': RunStepStatus.skipped},
              results: {
                's1': const RunbookStepResult(
                  step: step1,
                  success: false,
                  exitCode: 2,
                  output: 'boom',
                  attempts: 3,
                  errorMessage: 'Exit code 2 does not match expected 0',
                  durationMs: 42,
                ),
              },
            ),
          ],
        );
        final r =
            await get.execute(_ctx, {'runId': 'run-1'}) as Map<String, Object?>;
        final hostView = (r['hosts'] as List).single as Map<String, Object?>;
        expect(hostView['hostId'], 'h1');
        expect(hostView['status'], 'failed');
        final steps = (hostView['steps'] as List).cast<Map<String, Object?>>();
        expect(steps[0]['status'], 'failed');
        expect(steps[0]['exitCode'], 2);
        expect(steps[0]['attempts'], 3);
        expect(steps[0]['output'], 'boom');
        expect(steps[0]['error'], contains('Exit code 2'));
        expect(steps[1]['status'], 'skipped');
        expect(steps[1].containsKey('output'), isFalse);
      },
    );

    test('output is the last 8 KiB, with secrets masked', () async {
      track();
      const step1 = RunbookStepModel(
        id: 's1',
        runbookId: 'rb',
        stepOrder: 1,
        command: 'a',
      );
      final big = '${'x' * 20000}\nAKIAABCDEFGHIJKLMNOP\nEND';
      gateway.current = live(
        running: false,
        hosts: [
          host1(
            RunHostStatus.succeeded,
            steps: {'s1': RunStepStatus.success},
            results: {
              's1': RunbookStepResult(
                step: step1,
                success: true,
                exitCode: 0,
                output: big,
              ),
            },
          ),
        ],
      );
      final r =
          await get.execute(_ctx, {'runId': 'run-1'}) as Map<String, Object?>;
      final step =
          (((r['hosts'] as List).single as Map)['steps'] as List).first as Map;
      final output = step['output'] as String;
      expect(
        utf8.encode(output).length,
        lessThanOrEqualTo(kRunbookOutputTailBytes),
      );
      expect(output.endsWith('END'), isTrue);
      expect(output, isNot(contains('AKIAABCDEFGHIJKLMNOP')));
      expect(output, contains('[REDACTED'));
      expect(step['outputTruncated'], isTrue);
      expect(step['redactedCount'], 1);
    });

    test('waitSeconds returns as soon as the run settles', () async {
      track();
      gateway.current = live(running: true);
      final future = get.execute(_ctx, {'runId': 'run-1', 'waitSeconds': 30});

      await Future<void>.delayed(const Duration(milliseconds: 50));
      gateway.current = live(
        running: false,
        hosts: [host1(RunHostStatus.succeeded)],
      );
      gateway.done.complete();

      final sw = Stopwatch()..start();
      final r =
          await future.timeout(const Duration(seconds: 5))
              as Map<String, Object?>;
      expect(r['status'], 'succeeded');
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('waitSeconds returns the running state when the time is up', () async {
      track();
      gateway.current = live(running: true);
      final sw = Stopwatch()..start();
      final r =
          await get.execute(_ctx, {'runId': 'run-1', 'waitSeconds': 1})
              as Map<String, Object?>;
      expect(r['status'], 'running');
      expect(
        sw.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 900)),
      );
    });

    test('another client cannot read a run, live or stored', () async {
      track();
      gateway.current = live(running: true);
      await expectLater(
        get.execute(_other, {'runId': 'run-1'}),
        toolError(McpErrorCode.runNotFound),
      );
      await history.save(
        live(
          running: false,
          id: 'old-run',
          hosts: [host1(RunHostStatus.succeeded)],
        ),
      );
      gateway.current = null;
      await expectLater(
        get.execute(_other, {'runId': 'old-run'}),
        toolError(McpErrorCode.runNotFound),
      );
      await expectLater(
        get.execute(_ctx, {'runId': 'unknown'}),
        toolError(McpErrorCode.runNotFound),
      );
    });

    test(
      'a settled run is read back from history, for its own client only',
      () async {
        await history.save(
          live(
            running: false,
            id: 'old-run',
            hosts: [host1(RunHostStatus.succeeded)],
          ),
        );
        final r =
            await get.execute(_ctx, {'runId': 'old-run'})
                as Map<String, Object?>;
        expect(r['runId'], 'old-run');
        expect(r['status'], 'succeeded');
      },
    );

    test('a run started in the app is not readable by an agent', () async {
      await history.save(
        ActiveRun(
          id: 'ui-run',
          runbook: book(),
          running: false,
          startedAt: DateTime(2026),
          finishedAt: DateTime(2026),
          hosts: [host1(RunHostStatus.succeeded)],
        ),
      );
      await expectLater(
        get.execute(_ctx, {'runId': 'ui-run'}),
        toolError(McpErrorCode.runNotFound),
      );
    });

    test('waitSeconds is clamped to a minute', () {
      expect(GetRunbookRunTool.maxWaitSeconds, 60);
    });
  });

  group('cancel_runbook_run', () {
    ActiveRun live({bool running = true}) => ActiveRun(
      id: 'run-1',
      triggeredBy: const RunTrigger(
        clientId: 'client-1',
        clientName: 'Claude Code',
      ),
      runbook: RunbookModel(
        id: 'rb',
        workspaceId: 'ws',
        title: 'Release',
        createdAt: DateTime(2026),
      ),
      running: running,
      startedAt: DateTime(2026),
      hosts: const [],
    );

    test('cancels a run this client started, and logs it', () async {
      tracker.track(
        TrackedRun(
          runId: 'run-1',
          clientId: 'client-1',
          done: gateway.done.future,
        ),
      );
      gateway.current = live();
      gateway.isRunning = true;

      final r =
          await cancel.execute(_ctx, {'runId': 'run-1'})
              as Map<String, Object?>;
      expect(gateway.cancels, 1);
      expect(r['cancelRequested'], isTrue);
      final rows = await auditRows();
      expect(rows.single['tool'], 'cancel_runbook_run');
      expect(rows.single['decision'], 'allowed');
    });

    test('another client\'s run cannot be cancelled', () async {
      tracker.track(
        TrackedRun(
          runId: 'run-1',
          clientId: 'client-1',
          done: gateway.done.future,
        ),
      );
      gateway.current = live();
      await expectLater(
        cancel.execute(_other, {'runId': 'run-1'}),
        toolError(McpErrorCode.runNotFound),
      );
      await expectLater(
        cancel.execute(_ctx, {'runId': 'unknown'}),
        toolError(McpErrorCode.runNotFound),
      );
      expect(gateway.cancels, 0);
    });

    test('a finished run is reported, not an error', () async {
      tracker.track(
        TrackedRun(
          runId: 'run-1',
          clientId: 'client-1',
          done: gateway.done.future,
        ),
      );
      gateway.current = live(running: false);
      final r =
          await cancel.execute(_ctx, {'runId': 'run-1'})
              as Map<String, Object?>;
      expect(r['cancelRequested'], isFalse);
      expect(gateway.cancels, 0);
    });
  });

  group('tool definitions', () {
    test('the four tools are named and their required arguments declared', () {
      final defs = {
        for (final d in [
          list.definition,
          run.definition,
          get.definition,
          cancel.definition,
        ])
          d.name: d,
      };
      expect(defs.keys, [
        'list_runbooks',
        'run_runbook',
        'get_runbook_run',
        'cancel_runbook_run',
      ]);
      expect(defs['run_runbook']!.inputSchema['required'], [
        'runbookId',
        'hostIds',
      ]);
      expect(defs['get_runbook_run']!.inputSchema['required'], ['runId']);
      expect(defs['cancel_runbook_run']!.inputSchema['required'], ['runId']);
    });

    test(
      'snake_case argument names are read as their camelCase twins',
      () async {
        await host('h1');
        await runbook();
        final future = run.execute(_ctx, {
          'runbook_id': 'rb',
          'host_ids': ['h1'],
        });
        final request = await answer(
          const RunbookApprovalDecision(approved: true),
        );
        await future;
        expect(request.runbookTitle, 'Release');
        expect(gateway.started.single.hostIds, ['h1']);
      },
    );
  });
}
