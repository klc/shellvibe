import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../../core/mcp/mcp_protocol.dart';
import '../../../../shared/database/daos/hosts_dao.dart';
import '../../../hosts/data/repositories/hosts_repository.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../snippets/data/repositories/run_history_repository.dart';
import '../../../snippets/data/repositories/runbooks_repository.dart';
import '../../../snippets/data/repositories/snippets_repository.dart';
import '../../../snippets/domain/models/active_run.dart';
import '../../../snippets/domain/models/run_strategy.dart';
import '../../../snippets/domain/models/runbook_model.dart';
import '../../../snippets/domain/models/runbook_step_model.dart';
import '../../../snippets/domain/models/snippet_model.dart';
import '../../../snippets/domain/models/variable_declaration.dart';
import '../../../snippets/domain/services/run_variables.dart';
import '../../../snippets/domain/services/runbook_run_service.dart';
import '../../domain/models/mcp_enums.dart';
import '../../domain/models/mcp_models.dart';
import '../../domain/services/approval_coordinator.dart';
import '../../domain/services/output_redactor.dart';
import '../repositories/mcp_audit_repository.dart';
import '../repositories/mcp_grant_repository.dart';
import 'mcp_tool_handler.dart';

/// The run machinery the runbook tools drive: the same one the app's own run
/// view is built on, behind an interface so the tools are tested without it.
abstract class RunbookRunGateway {
  /// The run on screen, running or settled; null before any.
  ActiveRun? get current;

  bool get isRunning;

  /// Starts [runbook] on [hosts]. The run is registered by the time this
  /// returns its future, which completes when the run has settled and been
  /// recorded; callers do not await it unless they mean to wait for the end.
  Future<void> start(
    RunbookModel runbook,
    List<HostModel> hosts, {
    required Map<String, String> variableValues,
    required RunStrategy strategy,
    required RunTrigger triggeredBy,
    required String runId,
  });

  Future<void> cancel();
}

/// What the runbook tools know about runs they started in this app session.
///
/// Held in memory, shared by the three tools. A run started before the app
/// restarted is not in it; such a run is found through the history row, which
/// carries the client that started it, so only its owner can read it back
/// either way.
class RunbookRunTracker {
  final Map<String, TrackedRun> _runs = {};

  void track(TrackedRun run) => _runs[run.runId] = run;

  TrackedRun? find(String runId) => _runs[runId];
}

class TrackedRun {
  final String runId;
  final String clientId;

  /// Completes when the run has settled and been recorded.
  final Future<void> done;

  const TrackedRun({
    required this.runId,
    required this.clientId,
    required this.done,
  });
}

/// An agent's argument names are camelCase, like every other tool here; a
/// model that writes `runbook_id` anyway means the same thing, so snake_case
/// keys are read as their camelCase twins.
Map<String, Object?> _normalized(Map<String, Object?> args) {
  String camel(String key) => key.replaceAllMapped(
    RegExp(r'_([a-z])'),
    (m) => m.group(1)!.toUpperCase(),
  );
  return {for (final e in args.entries) camel(e.key): e.value};
}

/// `list_runbooks` — the curated operations the user has written down.
class ListRunbooksTool with McpArgReaders implements McpToolHandler {
  final RunbooksRepository runbooksRepository;
  final SnippetsRepository snippetsRepository;
  final HostsDao hostsDao;
  final OutputRedactor redactor;

  const ListRunbooksTool({
    required this.runbooksRepository,
    required this.snippetsRepository,
    required this.hostsDao,
    required this.redactor,
  });

  @override
  String get name => 'list_runbooks';

  @override
  McpToolDefinition get definition => McpToolDefinition(
    name: name,
    description:
        'Lists the runbooks in this client\'s workspace: multi-step '
        'operations the user wrote down in ShellVibe, each with its steps, '
        'the variables it asks for and the hosts it is usually run on. '
        'Prefer a runbook to improvising the same work with run_command: it '
        'is exactly what the user has already decided the operation is. '
        'A step is a command, a snippet (shown by title) or an approval '
        'gate (shown by its message). Variables list their type, whether '
        'they are required and, for a choice, the options; a "secret" '
        'variable cannot be passed by you: the user types it in the approval '
        'window. "defaultHostIds" are only hosts you may see. To run one, '
        'call run_runbook, which always asks the user.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description':
              'Only runbooks whose title, description, tags or step text '
              'contain this, ignoring case.',
        },
        'tag': {
          'type': 'string',
          'description': 'Only runbooks carrying exactly this tag.',
        },
      },
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> execute(McpToolContext ctx, Map<String, Object?> args) async {
    final query = optionalString(args, 'query')?.trim().toLowerCase();
    final tag = optionalString(args, 'tag');
    final runbooks = await runbooksRepository.getRunbooksByWorkspace(
      ctx.workspaceId,
    );
    final snippets = {
      for (final s in await snippetsRepository.getAllSnippets()) s.id: s,
    };

    final result = <Map<String, Object?>>[];
    for (final runbook in runbooks) {
      if (tag != null && !runbook.tags.contains(tag)) continue;
      if (query != null && query.isNotEmpty) {
        final haystack = [
          runbook.title,
          runbook.description ?? '',
          ...runbook.tags,
          for (final s in runbook.steps) s.command,
        ].join('\n').toLowerCase();
        if (!haystack.contains(query)) continue;
      }
      result.add(await _describe(ctx, runbook, snippets));
    }
    return {'runbooks': result};
  }

  Future<Map<String, Object?>> _describe(
    McpToolContext ctx,
    RunbookModel runbook,
    Map<String, SnippetModel> snippets,
  ) async {
    final steps = [...runbook.steps]
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
    final needed = collectRunVariables(runbook, snippets: snippets);

    // Default hosts the agent could not see anyway are not hinted at.
    final visible = <String>[];
    for (final id in runbook.defaultHostIds) {
      final row = await hostsDao.getHostById(id);
      if (row != null && row.workspaceId == ctx.workspaceId && row.mcpVisible) {
        visible.add(id);
      }
    }

    return {
      'id': runbook.id,
      'title': runbook.title,
      'description': runbook.description,
      'tags': runbook.tags,
      'steps': [for (final step in steps) _step(step, snippets, redactor)],
      'variables': [for (final d in needed.declarations) describeVariable(d)],
      'defaultHostIds': visible,
    };
  }

  /// One step as an agent reads it. Command text goes through the redactor: a
  /// runbook someone wrote may well have a literal token in a command.
  static Map<String, Object?> _step(
    RunbookStepModel step,
    Map<String, SnippetModel> snippets,
    OutputRedactor redactor,
  ) {
    final map = <String, Object?>{
      'order': step.stepOrder,
      'kind': step.kind.name,
    };
    switch (step.kind) {
      case StepKind.command:
        map['command'] = redactor.redact(step.command).text;
      case StepKind.snippet:
        map['snippet'] = snippets[step.snippetId]?.title ?? '(deleted snippet)';
      case StepKind.approval:
        map['message'] = step.command;
    }
    if (step.kind != StepKind.approval) {
      map['expectedExitCode'] = step.expectedExitCode;
      map['onFailure'] = step.onFailure.wireName;
      map['retries'] = step.retries;
      map['timeoutSeconds'] = step.timeoutSeconds;
      if (step.expectedOutputPattern != null) {
        map['expectedOutput'] = step.expectedOutputPattern;
      }
    }
    return map;
  }

  /// A variable as an agent sees it: never a default for a secret.
  static Map<String, Object?> describeVariable(VariableDeclaration d) => {
    'name': d.name,
    'type': d.type.wireName,
    'required': d.required,
    if (d.label != null) 'label': d.label,
    if (d.description != null) 'description': d.description,
    if (d.type == VariableType.enumeration) 'options': d.options,
    if (d.type != VariableType.secret && d.defaultValue != null)
      'defaultValue': d.defaultValue,
  };
}

/// The note an agent is given whenever a run is at an approval gate.
const String kApprovalStepNote =
    'This run is waiting at an approval step. It cannot be approved through '
    'MCP: the user has to press Continue in the ShellVibe window. Tell them, '
    'then keep polling get_runbook_run.';

/// The tail of a step's output an agent is given.
const int kRunbookOutputTailBytes = 8 * 1024;

/// A run as an agent reads it.
///
/// Output is the last [kRunbookOutputTailBytes] of each step, after the
/// redactor has been over it: the run's own secret-value masking already
/// happened (live results are masked as they arrive, stored ones when saved),
/// and the same masking `run_command` output gets is applied on top.
Map<String, Object?> describeRunbookRun(
  ActiveRun run, {
  OutputRedactor redactor = const OutputRedactor(),
}) {
  final steps = [...run.runbook.steps]
    ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));

  RunbookStepModel? waitingAt;
  for (final step in steps) {
    if (step.kind == StepKind.approval &&
        run.hosts.any((h) => h.steps[step.id] == RunStepStatus.waiting)) {
      waitingAt = step;
      break;
    }
  }

  final status = run.running
      ? (waitingAt != null ? 'waiting_for_approval' : 'running')
      : run.outcome;

  return {
    'runId': run.id,
    'runbook': run.runbook.title,
    'status': status,
    'strategy': run.strategy.label,
    'startedAt': run.startedAt.toUtc().toIso8601String(),
    if (run.finishedAt != null)
      'finishedAt': run.finishedAt!.toUtc().toIso8601String(),
    if (waitingAt != null) ...{
      'waitingFor': {'step': waitingAt.stepOrder, 'message': waitingAt.command},
      'note': kApprovalStepNote,
    },
    if (run.stoppedAfter != null) 'stoppedAfter': run.stoppedAfter,
    'hosts': [
      for (final host in run.hosts)
        {
          'hostId': host.hostId,
          'label': host.label,
          'status': host.status.name,
          if (host.error != null) 'error': host.error,
          'steps': [for (final step in steps) _stepView(step, host, redactor)],
        },
    ],
  };
}

Map<String, Object?> _stepView(
  RunbookStepModel step,
  HostRunState host,
  OutputRedactor redactor,
) {
  final result = host.results[step.id];
  final view = <String, Object?>{
    'order': step.stepOrder,
    'kind': step.kind.name,
    'status': (host.steps[step.id] ?? RunStepStatus.pending).name,
  };
  if (result == null) return view;
  view['exitCode'] = result.exitCode;
  view['attempts'] = result.attempts;
  if (result.durationMs != null) view['durationMs'] = result.durationMs;
  final redacted = redactor.redact(result.output);
  final (tail, cut) = _tail(redacted.text, kRunbookOutputTailBytes);
  view['output'] = tail;
  view['outputTruncated'] = cut || result.outputTruncated;
  if (redacted.count > 0) view['redactedCount'] = redacted.count;
  if (result.errorMessage != null) {
    view['error'] = redactor.redact(result.errorMessage!).text;
  }
  return view;
}

/// The last [limit] bytes of [text], on a character boundary.
(String, bool) _tail(String text, int limit) {
  final bytes = utf8.encode(text);
  if (bytes.length <= limit) return (text, false);
  final cut = utf8.decode(
    bytes.sublist(bytes.length - limit),
    allowMalformed: true,
  );
  return (cut.startsWith('\uFFFD') ? cut.substring(1) : cut, true);
}

/// `run_runbook` — start a runbook, after the user has said yes.
class RunRunbookTool with McpArgReaders implements McpToolHandler {
  final RunbooksRepository runbooksRepository;
  final SnippetsRepository snippetsRepository;
  final HostsRepository hostsRepository;
  final HostsDao hostsDao;
  final McpGrantRepository grantRepository;
  final McpAuditRepository auditRepository;
  final ApprovalCoordinator approvalCoordinator;
  final RunbookRunGateway gateway;
  final RunbookRunTracker tracker;
  final OutputRedactor redactor;

  const RunRunbookTool({
    required this.runbooksRepository,
    required this.snippetsRepository,
    required this.hostsRepository,
    required this.hostsDao,
    required this.grantRepository,
    required this.auditRepository,
    required this.approvalCoordinator,
    required this.gateway,
    required this.tracker,
    required this.redactor,
  });

  /// Refusals already written to the log with their own, richer entry.
  static final _audited = Expando<bool>();

  @override
  String get name => 'run_runbook';

  @override
  McpToolDefinition get definition => McpToolDefinition(
    name: name,
    description:
        'Starts a runbook (see list_runbooks) on one or more hosts and '
        'returns at once with a runId; the run goes on in ShellVibe. Every '
        'call pauses for the user to approve it in a window that shows the '
        'steps, the hosts (production is highlighted) and the values: there '
        'is no policy mode or earlier approval that skips this, because a '
        'runbook is several commands on several hosts. Every host must be '
        'visible to you and already granted (request_host_access first, or '
        'you get HOST_ACCESS_REQUIRED). Pass only non-secret variables; a '
        'secret variable is typed by the user in the approval window, and '
        'passing one is rejected. Required variables that are missing are '
        'reported before the user is asked anything. One run at a time: '
        'while another is in progress you get RUNBOOK_BUSY. Follow the run '
        'with get_runbook_run; stop it with cancel_runbook_run. An '
        'approval step in the runbook waits for the user to press Continue '
        'in ShellVibe: you cannot continue it.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'runbookId': {
          'type': 'string',
          'description': 'The id of the runbook, from list_runbooks.',
        },
        'hostIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': 1,
          'description':
              'The hosts to run it on: ids from list_hosts that you have '
              'been granted access to.',
        },
        'variables': {
          'type': 'object',
          'additionalProperties': {'type': 'string'},
          'description':
              'Values for the runbook\'s non-secret variables, by name. '
              'A variable with a default may be left out.',
        },
        'strategy': {
          'type': 'string',
          'enum': ['parallel', 'rolling'],
          'description':
              '"parallel" (default) runs several hosts at once; "rolling" '
              'runs one host at a time and stops at the first failure, '
              'leaving the rest unstarted: use it for a canary.',
        },
        'concurrency': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 8,
          'description':
              'With "parallel": how many hosts at once. Defaults to 4.',
        },
      },
      'required': ['runbookId', 'hostIds'],
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> execute(
    McpToolContext ctx,
    Map<String, Object?> rawArgs,
  ) async {
    final args = _normalized(rawArgs);
    final runbookId = requireString(args, 'runbookId');
    final hostIds = requireStringList(args, 'hostIds');

    try {
      return await _run(ctx, args, runbookId, hostIds);
    } on McpToolException catch (e) {
      if (_audited[e] ?? false) rethrow;
      // A request refused for what it asked is still a request: it goes in the
      // log as a refusal, with the reason.
      await auditRepository.record(
        clientId: ctx.clientId,
        clientName: ctx.clientName,
        tool: name,
        args: {
          'runbookId': runbookId,
          'hostIds': hostIds,
          'rejected': e.message,
        },
        decision: AuditDecision.denied,
      );
      rethrow;
    }
  }

  Future<Object?> _run(
    McpToolContext ctx,
    Map<String, Object?> args,
    String runbookId,
    List<String> hostIds,
  ) async {
    final runbook = (await runbooksRepository.getRunbooksByWorkspace(
      ctx.workspaceId,
    )).where((r) => r.id == runbookId).firstOrNull;
    if (runbook == null) {
      throw McpToolException(
        McpErrorCode.runbookNotFound,
        'No runbook with id "$runbookId" in this workspace. Call '
        'list_runbooks to see the ids.',
      );
    }

    final strategy = _strategy(args);
    final hosts = await _resolveHosts(ctx, hostIds);

    final snippets = {
      for (final s in await snippetsRepository.getAllSnippets()) s.id: s,
    };
    final needed = collectRunVariables(runbook, snippets: snippets);
    final plain = _checkVariables(args['variables'], needed);
    final secretFields = [
      for (final d in needed.declarations)
        if (d.type == VariableType.secret)
          RunbookSecretField(
            name: d.name,
            label: d.displayLabel,
            required: d.required,
            description: d.description,
          ),
    ];

    // Busy is answered before the user is asked: there is nothing to approve
    // while another run holds the one slot.
    if (gateway.isRunning) throw _busy();

    final steps = [...runbook.steps]
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
    final decision = await approvalCoordinator.requestRunbookApproval(
      RunbookApprovalRequest(
        clientId: ctx.clientId,
        clientName: ctx.clientName,
        runbookTitle: runbook.title,
        strategyLabel: strategy.label,
        variables: plain,
        secretFields: secretFields,
        steps: [
          for (final step in steps)
            RunbookApprovalStep(
              order: step.stepOrder,
              kind: step.kind.name,
              text: switch (step.kind) {
                StepKind.snippet =>
                  snippets[step.snippetId]?.code ?? step.command,
                _ => step.command,
              },
            ),
        ],
        hosts: [
          for (final row in hosts)
            RunbookApprovalHost(
              id: row.host.id,
              label: row.host.label,
              environment: row.environment,
            ),
        ],
      ),
    );

    final audited = {
      'runbookId': runbook.id,
      'runbookTitle': runbook.title,
      'hostIds': hostIds,
      'strategy': strategy.wireName,
      // Names only: a value may be a credential, and the log is not the place.
      'variables': [...plain.keys, ...secretFields.map((f) => f.name)],
    };
    final hostLabels = hosts.map((h) => h.host.label).join(', ');

    if (!decision.approved) {
      await auditRepository.record(
        clientId: ctx.clientId,
        clientName: ctx.clientName,
        hostLabel: hostLabels,
        tool: name,
        args: audited,
        decision: AuditDecision.denied,
      );
      final declined = McpToolException(
        McpErrorCode.policyDenied,
        'The user declined to run "${runbook.title}".',
      );
      _audited[declined] = true;
      throw declined;
    }

    // The answer to the prompt may have taken a minute: someone else may have
    // started a run meanwhile.
    if (gateway.isRunning) {
      await auditRepository.record(
        clientId: ctx.clientId,
        clientName: ctx.clientName,
        hostLabel: hostLabels,
        tool: name,
        args: audited,
        decision: AuditDecision.error,
      );
      final busy = _busy();
      _audited[busy] = true;
      throw busy;
    }

    final runId = const Uuid().v4();
    final started = DateTime.now();
    final done = gateway.start(
      runbook,
      [for (final row in hosts) row.host],
      variableValues: {...plain, ...decision.secretValues},
      strategy: strategy,
      triggeredBy: RunTrigger(
        clientId: ctx.clientId,
        clientName: ctx.clientName,
      ),
      runId: runId,
    );
    tracker.track(TrackedRun(runId: runId, clientId: ctx.clientId, done: done));

    await auditRepository.record(
      clientId: ctx.clientId,
      clientName: ctx.clientName,
      hostLabel: hostLabels,
      tool: name,
      args: {...audited, 'runId': runId},
      decision: AuditDecision.confirmed,
    );
    // The outcome is logged when the run ends, not when it starts.
    unawaited(
      done
          .then((_) async {
            final run = gateway.current;
            final outcome = run != null && run.id == runId
                ? run.outcome
                : 'unknown';
            await auditRepository.record(
              clientId: ctx.clientId,
              clientName: ctx.clientName,
              hostLabel: hostLabels,
              tool: name,
              args: {'runId': runId, 'outcome': outcome},
              decision: outcome == 'succeeded'
                  ? AuditDecision.confirmed
                  : AuditDecision.error,
              durationMs: DateTime.now().difference(started).inMilliseconds,
            );
          })
          .catchError((Object _) {}),
    );

    final run = gateway.current;
    return {
      if (run != null && run.id == runId)
        ...describeRunbookRun(run, redactor: redactor)
      else ...{
        'runId': runId,
        'status': 'running',
      },
      'note':
          'Started. Poll get_runbook_run with this runId (waitSeconds lets '
          'you wait for it); cancel_runbook_run stops it.',
    };
  }

  McpToolException _busy() => McpToolException(
    McpErrorCode.runbookBusy,
    'A runbook run is already in progress, and only one runs at a time. '
    'Follow it with get_runbook_run, or wait for it to finish.',
  );

  RunStrategy _strategy(Map<String, Object?> args) {
    final mode = optionalString(args, 'strategy') ?? 'parallel';
    final concurrency = optionalInt(args, 'concurrency');
    if (mode != 'parallel' && mode != 'rolling') {
      throw McpToolException(
        McpErrorCode.internal,
        'Argument "strategy" must be "parallel" or "rolling", got "$mode".',
      );
    }
    if (concurrency != null &&
        (concurrency < 1 || concurrency > RunStrategy.maxConcurrency)) {
      throw McpToolException(
        McpErrorCode.internal,
        'Argument "concurrency" must be between 1 and '
        '${RunStrategy.maxConcurrency}, got $concurrency.',
      );
    }
    return mode == 'rolling'
        ? const RunStrategy.rolling()
        : RunStrategy.parallel(concurrency ?? RunStrategy.defaultConcurrency);
  }

  /// Every host must exist in this workspace, be visible to MCP and be
  /// granted to this client. Anything else is the same answer a hidden host
  /// gets everywhere: the agent cannot tell "missing" from "not yours".
  Future<List<({HostModel host, HostEnvironment environment})>> _resolveHosts(
    McpToolContext ctx,
    List<String> hostIds,
  ) async {
    final resolved = <({HostModel host, HostEnvironment environment})>[];
    final seen = <String>{};
    for (final id in hostIds) {
      if (!seen.add(id)) continue;
      final host = await hostsRepository.getHostById(id);
      final row = await hostsDao.getHostById(id);
      if (host == null ||
          host.workspaceId != ctx.workspaceId ||
          row == null ||
          !row.mcpVisible) {
        throw McpToolException(
          McpErrorCode.hostNotVisible,
          'No host with id "$id" is visible to this client.',
        );
      }
      if (await grantRepository.effectiveMode(ctx.clientId, id) == null) {
        throw McpToolException(
          McpErrorCode.hostAccessRequired,
          'Access to host "$id" has not been granted. Call '
          'request_host_access for it first.',
        );
      }
      if (host.protocol == 'local') {
        throw McpToolException(
          McpErrorCode.internal,
          'Host "$id" is a local shell, which a runbook cannot run on in the '
          'background.',
        );
      }
      resolved.add((
        host: host,
        environment: HostEnvironment.fromName(row.environment),
      ));
    }
    return resolved;
  }

  /// The values an agent supplied, checked against what the runbook asks for,
  /// merged with defaults. Throws before any prompt: a request that cannot run
  /// is not worth the user's attention.
  Map<String, String> _checkVariables(Object? raw, RunVariables needed) {
    if (raw != null && raw is! Map) {
      throw McpToolException(
        McpErrorCode.invalidVariables,
        'Argument "variables" must be an object of strings.',
      );
    }
    final given = <String, String>{};
    for (final entry in ((raw as Map?) ?? const {}).entries) {
      if (entry.value is! String) {
        throw McpToolException(
          McpErrorCode.invalidVariables,
          'Variable "${entry.key}" must be a string.',
        );
      }
      given['${entry.key}'] = entry.value as String;
    }

    final byName = {for (final d in needed.declarations) d.name: d};
    final unknown = given.keys.where((k) => !byName.containsKey(k)).toList();
    if (unknown.isNotEmpty) {
      throw McpToolException(
        McpErrorCode.invalidVariables,
        'This runbook has no variable named ${unknown.map((u) => '"$u"').join(', ')}. '
        'Its variables: ${byName.isEmpty ? '(none)' : byName.keys.join(', ')}.',
      );
    }
    final secrets = given.keys
        .where((k) => byName[k]!.type == VariableType.secret)
        .toList();
    if (secrets.isNotEmpty) {
      throw McpToolException(
        McpErrorCode.invalidVariables,
        'Variable ${secrets.map((s) => '"$s"').join(', ')} is a secret: you '
        'cannot pass it. Leave it out and the user types it in the approval '
        'window.',
      );
    }

    final values = <String, String>{};
    final missing = <String>[];
    for (final d in needed.declarations) {
      if (d.type == VariableType.secret) continue;
      final value = given[d.name] ?? d.defaultValue;
      if (value == null || value.isEmpty) {
        if (d.required) missing.add(d.name);
        if (!d.required) values[d.name] = '';
        continue;
      }
      if (d.type == VariableType.enumeration && !d.options.contains(value)) {
        throw McpToolException(
          McpErrorCode.invalidVariables,
          'Variable "${d.name}" must be one of ${d.options.join(', ')}, got '
          '"$value".',
        );
      }
      values[d.name] = value;
    }
    if (missing.isNotEmpty) {
      throw McpToolException(
        McpErrorCode.invalidVariables,
        'Missing required variable${missing.length == 1 ? '' : 's'}: '
        '${missing.join(', ')}. Pass ${missing.length == 1 ? 'it' : 'them'} in "variables".',
      );
    }
    return values;
  }
}

/// `get_runbook_run` — where a run you started stands.
class GetRunbookRunTool with McpArgReaders implements McpToolHandler {
  final RunbookRunGateway gateway;
  final RunbookRunTracker tracker;
  final RunHistoryRepository historyRepository;
  final OutputRedactor redactor;

  const GetRunbookRunTool({
    required this.gateway,
    required this.tracker,
    required this.historyRepository,
    required this.redactor,
  });

  static const int maxWaitSeconds = 60;

  @override
  String get name => 'get_runbook_run';

  @override
  McpToolDefinition get definition => McpToolDefinition(
    name: name,
    description:
        'Reports a runbook run you started with run_runbook: an overall '
        'status ("running", "waiting_for_approval", "succeeded", "failed" '
        'or "cancelled"), each host\'s status and error, and each step\'s '
        'status, exit code, attempts and output (the last 8 KiB, with '
        'secrets masked). Works for the run in progress and for finished '
        'ones. waitSeconds holds the call open until the run settles or the '
        'time runs out, so you need not poll in a tight loop. When the '
        'status is "waiting_for_approval" the user has to press Continue in '
        'ShellVibe: you cannot. You can only read runs you started.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'runId': {
          'type': 'string',
          'description': 'The runId run_runbook returned.',
        },
        'waitSeconds': {
          'type': 'integer',
          'minimum': 0,
          'maximum': maxWaitSeconds,
          'description':
              'Wait up to this long for the run to settle before answering. '
              'Defaults to 0: answer at once.',
        },
      },
      'required': ['runId'],
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> execute(
    McpToolContext ctx,
    Map<String, Object?> rawArgs,
  ) async {
    final args = _normalized(rawArgs);
    final runId = requireString(args, 'runId');
    final wait = (optionalInt(args, 'waitSeconds') ?? 0).clamp(
      0,
      maxWaitSeconds,
    );

    final tracked = tracker.find(runId);
    if (tracked != null && tracked.clientId != ctx.clientId) {
      throw _notFound(runId);
    }

    if (tracked != null && wait > 0) {
      final live = gateway.current;
      if (live != null && live.id == runId && live.running) {
        await Future.any<void>([
          tracked.done,
          Future<void>.delayed(Duration(seconds: wait)),
        ]);
      }
    }

    final live = gateway.current;
    if (live != null && live.id == runId && tracked != null) {
      return describeRunbookRun(live, redactor: redactor);
    }

    // Settled and replaced on screen, or from before the app restarted: the
    // history row, readable only by the client that started it.
    final stored = await historyRepository.load(runId);
    final owner = stored?.run.triggeredBy?.clientId;
    if (stored == null || owner != ctx.clientId) throw _notFound(runId);
    return describeRunbookRun(stored.run, redactor: redactor);
  }

  McpToolException _notFound(String runId) => McpToolException(
    McpErrorCode.runNotFound,
    'No run with id "$runId" that this client started.',
  );
}

/// `cancel_runbook_run` — stop a run you started.
class CancelRunbookRunTool with McpArgReaders implements McpToolHandler {
  final RunbookRunGateway gateway;
  final RunbookRunTracker tracker;
  final McpAuditRepository auditRepository;
  final OutputRedactor redactor;

  const CancelRunbookRunTool({
    required this.gateway,
    required this.tracker,
    required this.auditRepository,
    required this.redactor,
  });

  @override
  String get name => 'cancel_runbook_run';

  @override
  McpToolDefinition get definition => McpToolDefinition(
    name: name,
    description:
        'Stops a runbook run you started: running commands are interrupted, '
        'the connections are closed and steps that had not run are marked '
        'cancelled. A run that has already finished is reported as it '
        'ended, not an error. You can only cancel runs you started.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'runId': {
          'type': 'string',
          'description': 'The runId run_runbook returned.',
        },
      },
      'required': ['runId'],
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> execute(
    McpToolContext ctx,
    Map<String, Object?> rawArgs,
  ) async {
    final args = _normalized(rawArgs);
    final runId = requireString(args, 'runId');
    final tracked = tracker.find(runId);
    if (tracked == null || tracked.clientId != ctx.clientId) {
      throw McpToolException(
        McpErrorCode.runNotFound,
        'No run with id "$runId" that this client started and can still '
        'cancel.',
      );
    }

    final live = gateway.current;
    final active = live != null && live.id == runId && live.running;
    if (active) await gateway.cancel();

    await auditRepository.record(
      clientId: ctx.clientId,
      clientName: ctx.clientName,
      tool: name,
      args: {'runId': runId, 'wasRunning': active},
      decision: AuditDecision.allowed,
    );

    final after = gateway.current;
    if (after != null && after.id == runId) {
      return {
        ...describeRunbookRun(after, redactor: redactor),
        'cancelRequested': active,
      };
    }
    return {'runId': runId, 'cancelRequested': active};
  }
}
