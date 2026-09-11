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
import 'command_tools.dart';
import 'discovery_tools.dart';
import 'mcp_tool_handler.dart';
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

  McpToolRegistry(List<McpToolHandler> handlers)
    : _handlersByName = {for (final handler in handlers) handler.name: handler};

  /// The `tools/list` payload: one [McpToolDefinition] per registered tool.
  List<McpToolDefinition> definitions() =>
      _handlersByName.values.map((handler) => handler.definition).toList();

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
    return handler.execute(ctx, args);
  }
}

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

  return McpToolRegistry([
    ListHostsTool(
      hostsRepository: hostsRepository,
      hostsDao: hostsDao,
      grantRepository: grantRepository,
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
    ),
    OpenSessionTool(
      sessionPool: sessionPool,
      hostsRepository: hostsRepository,
      grantRepository: grantRepository,
    ),
    ListSessionsTool(sessionPool: sessionPool),
    CloseSessionTool(sessionPool: sessionPool),
    InterruptTool(sessionPool: sessionPool),
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
  ]);
}
