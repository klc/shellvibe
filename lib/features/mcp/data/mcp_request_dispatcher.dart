import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/mcp/mcp_protocol.dart';
import '../../../shared/providers/database_providers.dart';
import '../domain/models/mcp_models.dart';
import 'repositories/mcp_repository_providers.dart';
import 'tools/mcp_tool_handler.dart';
import 'tools/mcp_tool_registry.dart';

part 'mcp_request_dispatcher.g.dart';

/// Name and version this server reports to a client during `initialize`.
const _kServerInfo = McpServerInfo(name: 'ShellVibe', version: '1');

/// Turns a JSON-RPC request into an MCP response by routing it to the tool
/// registry.
///
/// This is the piece that makes the transport and the tools one system: the
/// transport knows how to authenticate and frame, the registry knows how to
/// run a tool, and nothing else knows both. [McpServerController] takes this
/// as its `onRequest` callback.
///
/// **Why tool failures come back as successful JSON-RPC responses.** MCP
/// distinguishes a *protocol* error (the client sent something the server
/// cannot process — a bad method, malformed params) from a *tool* error (the
/// tool ran and refused, or failed). Only the first is a JSON-RPC error
/// frame. A refusal like `POLICY_DENIED` is a normal `tools/call` result with
/// `isError: true`, because the agent is supposed to read it, understand why,
/// and adapt — a JSON-RPC error frame would look to most clients like the
/// server broke rather than like an answer.
class McpRequestDispatcher {
  final McpToolRegistry registry;

  /// Resolves the display name and workspace of an authenticated client.
  ///
  /// Taken as a callback rather than a repository so this class stays
  /// testable without a database, and so the lookup can be cached later
  /// without touching dispatch.
  final Future<({String name, String workspaceId})?> Function(String clientId)
  lookupClient;

  /// Called with the scope of a connection that has ended, so what it scoped
  /// to "this session" can be dropped.
  final void Function(String connectionScopeId)? onScopeEnded;

  /// Identifies each client's current MCP connection, so approvals scoped to
  /// "this session" end with it.
  ///
  /// Per client: two agents connected at once are two sessions, and one of
  /// them reconnecting must not end the other's. A client that reconnects
  /// re-runs `initialize`, which is where its fresh scope is minted.
  final Map<String, String> _connectionScopes = {};

  McpRequestDispatcher({
    required this.registry,
    required this.lookupClient,
    this.onScopeEnded,
  });

  /// The scope of [clientId]'s current connection.
  String connectionScopeFor(String clientId) =>
      _connectionScopes.putIfAbsent(clientId, const Uuid().v4);

  /// Ends every client's current connection scope. Called when the server
  /// stops: no connection survives that, so nothing scoped to "this session"
  /// may answer for whatever connects after a restart.
  void endAllScopes() {
    final ended = _connectionScopes.values.toList();
    _connectionScopes.clear();
    for (final scope in ended) {
      onScopeEnded?.call(scope);
    }
  }

  Future<Object?> handle(String clientId, JsonRpcRequest request) async {
    switch (request.method) {
      case McpMethod.ping:
        return const <String, Object?>{};

      case McpMethod.initialize:
        // A new handshake means a new connection, so anything the previous
        // one scoped to "this session" must not carry over to it.
        final ended = _connectionScopes[clientId];
        _connectionScopes[clientId] = const Uuid().v4();
        if (ended != null) onScopeEnded?.call(ended);
        return McpInitializeResult(serverInfo: _kServerInfo).toJson();

      case McpMethod.toolsList:
        return {
          'tools': registry.definitions().map((d) => d.toJson()).toList(),
        };

      case McpMethod.toolsCall:
        return (await _callTool(clientId, request)).toJson();

      default:
        throw McpDispatchException(
          JsonRpcError.methodNotFound,
          'Unknown method "${request.method}".',
        );
    }
  }

  Future<McpToolResult> _callTool(
    String clientId,
    JsonRpcRequest request,
  ) async {
    final name = request.params['name'];
    if (name is! String || name.isEmpty) {
      throw McpDispatchException(
        JsonRpcError.invalidParams,
        'tools/call requires a "name" string naming the tool to run.',
      );
    }

    final rawArgs = request.params['arguments'];
    if (rawArgs != null && rawArgs is! Map) {
      throw McpDispatchException(
        JsonRpcError.invalidParams,
        'tools/call "arguments" must be an object.',
      );
    }
    final args = rawArgs == null
        ? const <String, Object?>{}
        : Map<String, Object?>.from(rawArgs as Map);

    final client = await lookupClient(clientId);
    if (client == null) {
      // The token authenticated a moment ago, so this means the client was
      // revoked mid-conversation. Say so plainly instead of failing as a
      // generic internal error, so the agent stops retrying.
      return McpToolResult.error(
        'This client has been revoked. Ask the user to issue a new token in '
        'ShellVibe under Settings → AI Access.',
      );
    }

    final ctx = McpToolContext(
      clientId: clientId,
      clientName: client.name,
      workspaceId: client.workspaceId,
      connectionScopeId: connectionScopeFor(clientId),
    );

    try {
      return McpToolResult.json(await registry.call(ctx, name, args));
    } on McpToolException catch (e) {
      // A refusal is an answer, not a transport failure — see the class
      // docstring. The wire code travels in the payload so the agent can
      // branch on it rather than parse prose.
      return McpToolResult(
        content: [
          {'type': 'text', 'text': _encodeToolError(e)},
        ],
        isError: true,
      );
    } on McpDispatchException {
      // Genuinely a protocol-level problem; it belongs in a JSON-RPC error
      // frame, not in a tool result.
      rethrow;
    } on Object catch (e) {
      // Everything the tool layer did not model as an [McpToolException]
      // still has to reach the agent as something it can act on. Letting it
      // escape produces a bare `-32603 Internal error`, from which a
      // credential that cannot be decrypted, an unreachable server and an
      // outright bug all look identical — and none of them tell the agent
      // whether to retry, pick another host, or ask the user to fix
      // something.
      //
      // These messages name the failing subsystem and the record involved,
      // never a secret's value.
      return McpToolResult.error('$name failed: $e');
    }
  }

  String _encodeToolError(McpToolException e) {
    final payload = e.toJson();
    return payload.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
  }
}

/// A protocol-level failure that must be returned as a JSON-RPC error frame
/// rather than as a tool result — an unknown method, or malformed params.
class McpDispatchException implements Exception {
  final int code;
  final String message;

  const McpDispatchException(this.code, this.message);

  @override
  String toString() => 'McpDispatchException($code): $message';
}

/// Provider for [McpRequestDispatcher].
///
/// `keepAlive` because the server holds it for its whole lifetime; an
/// auto-disposing dispatcher would mint a new connection scope the first time
/// no widget happened to be watching it.
@Riverpod(keepAlive: true)
McpRequestDispatcher mcpRequestDispatcher(Ref ref) {
  final registry = ref.watch(mcpToolRegistryProvider);
  final dao = ref.watch(mcpDaoProvider);
  final approvals = ref.watch(mcpApprovalRepositoryProvider);
  final grants = ref.watch(mcpGrantRepositoryProvider);

  // A new dispatcher is a new server: no connection from before it is still
  // open, so nothing scoped to one of them may keep answering.
  unawaited(approvals.revokeSessionScoped());
  unawaited(grants.revokeSessionScoped());

  return McpRequestDispatcher(
    registry: registry,
    lookupClient: (clientId) async {
      final row = await dao.getClientById(clientId);
      if (row == null) return null;
      return (name: row.name, workspaceId: row.workspaceId);
    },
    onScopeEnded: (scope) {
      unawaited(approvals.revokeByConnectionScope(scope));
      unawaited(grants.revokeByConnectionScope(scope));
    },
  );
}
