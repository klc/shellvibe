import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/mcp/mcp_protocol.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../domain/models/mcp_enums.dart';
import '../../domain/models/mcp_models.dart';
import '../../domain/services/mcp_service_providers.dart';
import '../../domain/services/output_redactor.dart';
import '../mcp_providers.dart';
import '../repositories/mcp_repository_providers.dart';
import '../runbook_run_gateway.dart';
import '../../../snippets/data/run_providers.dart';
import '../../../snippets/presentation/notifiers/runbooks_notifier.dart';
import '../../../snippets/presentation/notifiers/snippets_notifier.dart';
import 'command_tools.dart';
import 'discovery_tools.dart';
import 'file_transfer_tools.dart';
import 'host_tools.dart';
import 'mcp_tool_handler.dart';
import 'runbook_tools.dart';
import 'session_tools.dart';

part 'mcp_tool_registry.g.dart';

/// Every v0 MCP tool, keyed by wire name.
///
/// This is the whole `tools/list` / `tools/call` surface the transport layer
/// talks to — it never sees an individual handler, only this registry.
/// Handlers are constructed once (via the provider below) and reused across
/// calls; they hold no per-call state of their own, only the shared
/// dependencies (session pool, repositories, policy engine, ...) each tool
/// needs.
class McpToolRegistry {
  final Map<String, McpToolHandler> _handlersByName;

  /// The groups the user switched off, read on every list and call so a
  /// switch applies to the next request.
  final McpToolSwitches switches;

  McpToolRegistry(List<McpToolHandler> handlers, {McpToolSwitches? switches})
    : _handlersByName = {for (final handler in handlers) handler.name: handler},
      switches = switches ?? McpToolSwitches();

  /// The `tools/list` payload: one [McpToolDefinition] per tool that is on.
  List<McpToolDefinition> definitions() => [
    for (final handler in _handlersByName.values)
      if (_offGroup(handler.name) == null) handler.definition,
  ];

  McpToolGroup? _offGroup(String tool) {
    final group = McpToolGroup.of(tool);
    return switches.disabled.contains(group) ? group : null;
  }

  /// Dispatches a `tools/call` by name. An unrecognized [name] is a protocol
  /// error, not a domain one — thrown with [McpErrorCode.internal] since no
  /// more specific code fits "the agent asked for a tool that does not
  /// exist," which should not normally happen against a client that just
  /// read `tools/list`.
  Future<Object?> call(
    McpToolContext ctx,
    String name,
    Map<String, Object?> args,
  ) {
    final handler = _handlersByName[name];
    if (handler == null) {
      throw McpToolException(
        McpErrorCode.internal,
        'Unknown tool "$name". Call tools/list to see the available tools.',
      );
    }
    // An agent that listed tools before the switch still has this one.
    final off = _offGroup(name);
    if (off != null) {
      throw McpToolException(
        McpErrorCode.toolDisabled,
        'The user turned off "${off.label}" for AI agents in ShellVibe '
        '(Settings > AI Access). Do not reach the host another way (ssh, scp, '
        'a script); tell the user this task needs it.',
      );
    }
    return handler.execute(ctx, args);
  }
}

/// Which [McpToolGroup]s are off. Filled by the AI Access settings, read by
/// [McpToolRegistry]: a plain holder, like the session pool's limits, so the
/// settings can change it without rebuilding the registry.
class McpToolSwitches {
  Set<McpToolGroup> disabled = const {};
}

@Riverpod(keepAlive: true)
McpToolSwitches mcpToolSwitches(Ref ref) => McpToolSwitches();

/// Provider for [McpToolRegistry].
///
/// `keepAlive`, matching every other provider in this feature that backs a
/// live MCP connection (see `mcp_providers.dart`): an autoDispose registry
/// would be torn down and rebuilt on whatever unrelated widget-tree churn
/// happens to drop its last watcher, which has nothing to do with whether an
/// agent is still connected.
@Riverpod(keepAlive: true)
McpToolRegistry mcpToolRegistry(Ref ref) {
  final hostsRepository = ref.watch(hostsRepositoryProvider);
  final hostsDao = ref.watch(hostsDaoProvider);
  final grantRepository = ref.watch(mcpGrantRepositoryProvider);
  final approvalRepository = ref.watch(mcpApprovalRepositoryProvider);
  final auditRepository = ref.watch(mcpAuditRepositoryProvider);
  final sessionPool = ref.watch(mcpSessionPoolProvider);
  final policyEngine = ref.watch(policyEngineProvider);
  final approvalCoordinator = ref.watch(approvalCoordinatorProvider);
  const redactor = OutputRedactor();
  final runbooksRepository = ref.watch(runbooksRepositoryProvider);
  final snippetsRepository = ref.watch(snippetsRepositoryProvider);
  final runGateway = NotifierRunbookRunGateway(ref);
  final runTracker = RunbookRunTracker();

  return McpToolRegistry(switches: ref.watch(mcpToolSwitchesProvider), [
    ListHostsTool(
      hostsRepository: hostsRepository,
      hostsDao: hostsDao,
      grantRepository: grantRepository,
      workspacesDao: ref.watch(appDatabaseProvider).workspacesDao,
    ),
    DescribeHostTool(
      hostsRepository: hostsRepository,
      hostsDao: hostsDao,
      grantRepository: grantRepository,
    ),
    RequestHostAccessTool(
      hostsRepository: hostsRepository,
      hostsDao: hostsDao,
      grantRepository: grantRepository,
      approvalCoordinator: approvalCoordinator,
      auditRepository: auditRepository,
    ),
    AddHostTool(
      hostsRepository: hostsRepository,
      identitiesDao: ref.watch(appDatabaseProvider).identitiesDao,
      auditRepository: auditRepository,
      approvalCoordinator: approvalCoordinator,
      onHostAdded: () => ref.invalidate(hostsProvider),
    ),
    OpenSessionTool(
      sessionPool: sessionPool,
      hostsRepository: hostsRepository,
      hostsDao: hostsDao,
      grantRepository: grantRepository,
      auditRepository: auditRepository,
    ),
    ListSessionsTool(sessionPool: sessionPool),
    CloseSessionTool(
      sessionPool: sessionPool,
      auditRepository: auditRepository,
    ),
    InterruptTool(sessionPool: sessionPool, auditRepository: auditRepository),
    RunCommandTool(
      sessionPool: sessionPool,
      hostsDao: hostsDao,
      grantRepository: grantRepository,
      approvalRepository: approvalRepository,
      auditRepository: auditRepository,
      policyEngine: policyEngine,
      approvalCoordinator: approvalCoordinator,
      redactor: redactor,
    ),
    FileTransferTool.upload(
      sessionPool: sessionPool,
      hostsDao: hostsDao,
      grantRepository: grantRepository,
      auditRepository: auditRepository,
      policyEngine: policyEngine,
      approvalCoordinator: approvalCoordinator,
    ),
    FileTransferTool.download(
      sessionPool: sessionPool,
      hostsDao: hostsDao,
      grantRepository: grantRepository,
      auditRepository: auditRepository,
      policyEngine: policyEngine,
      approvalCoordinator: approvalCoordinator,
    ),
    ListRunbooksTool(
      runbooksRepository: runbooksRepository,
      snippetsRepository: snippetsRepository,
      hostsDao: hostsDao,
      redactor: redactor,
    ),
    RunRunbookTool(
      runbooksRepository: runbooksRepository,
      snippetsRepository: snippetsRepository,
      hostsRepository: hostsRepository,
      hostsDao: hostsDao,
      grantRepository: grantRepository,
      auditRepository: auditRepository,
      approvalCoordinator: approvalCoordinator,
      gateway: runGateway,
      tracker: runTracker,
      redactor: redactor,
    ),
    ListSnippetsTool(
      snippetsRepository: snippetsRepository,
      redactor: redactor,
    ),
    RunRunbookTool.snippet(
      runbooksRepository: runbooksRepository,
      snippetsRepository: snippetsRepository,
      hostsRepository: hostsRepository,
      hostsDao: hostsDao,
      grantRepository: grantRepository,
      auditRepository: auditRepository,
      approvalCoordinator: approvalCoordinator,
      gateway: runGateway,
      tracker: runTracker,
      redactor: redactor,
    ),
    GetRunbookRunTool(
      gateway: runGateway,
      tracker: runTracker,
      historyRepository: ref.watch(runHistoryRepositoryProvider),
      redactor: redactor,
    ),
    CancelRunbookRunTool(
      gateway: runGateway,
      tracker: runTracker,
      auditRepository: auditRepository,
      redactor: redactor,
    ),
  ]);
}
