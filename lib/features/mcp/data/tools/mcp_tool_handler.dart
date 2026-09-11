import 'dart:convert';

import '../../../../core/mcp/mcp_protocol.dart';
import '../../domain/models/mcp_enums.dart';
import '../../domain/models/mcp_models.dart';

/// Everything one `tools/call` needs to know about who is calling it.
///
/// Built by the transport layer from the authenticated [McpClient] row, not
/// by the handler itself — a handler never sees a bearer token, only the
/// identity it already resolved to.
class McpToolContext {
  final String clientId;
  final String clientName;

  /// The workspace this client is bound to at registration time. Per
  /// `docs/mcp_plan.md` ("Workspace bağlama"), this comes from the client's
  /// own row, not from whatever workspace the user currently has open in the
  /// UI — an agent's reach must not shift under it because a human clicked
  /// to a different workspace.
  final String workspaceId;

  /// Identifies this MCP connection so 'this session' grants and approvals can
  /// be dropped when the agent disconnects.
  final String connectionScopeId;

  const McpToolContext({
    required this.clientId,
    required this.clientName,
    required this.workspaceId,
    required this.connectionScopeId,
  });
}

/// One MCP tool: its wire definition for `tools/list`, and its behavior for
/// `tools/call`.
///
/// Implementations live in `data/` (not `domain/`) because every v0 handler
/// touches the session pool, repositories, or both — this is orchestration,
/// not policy. The policy decisions themselves stay in `domain/services`.
abstract class McpToolHandler {
  /// Wire name the agent calls this tool by, e.g. `"list_hosts"`. Must match
  /// [definition]'s `name`.
  String get name;

  McpToolDefinition get definition;

  /// Runs the tool. Returns whatever JSON-encodable value belongs in the
  /// tool's success payload, or throws [McpToolException] for any failure
  /// the agent should be told about by machine-readable code.
  Future<Object?> execute(McpToolContext ctx, Map<String, Object?> args);
}

/// Argument-reading helpers shared by every handler.
///
/// An agent is a model guessing at a JSON Schema, not a compiler — it will
/// occasionally send a string where an array was declared, or omit a
/// required field. Centralizing the type checks here means that mistake
/// produces one precise [McpToolException] naming the argument and what was
/// expected, instead of a raw `TypeError`/`NoSuchMethodError` the agent has
/// no way to act on. Every failure uses [McpErrorCode.internal] — a bad
/// argument is a client-side protocol error, not one of the more specific
/// domain failures the other codes exist for.
mixin McpArgReaders {
  String requireString(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is! String || value.isEmpty) {
      throw McpToolException(
        McpErrorCode.internal,
        'Argument "$key" must be a non-empty string, got ${_describe(value)}.',
      );
    }
    return value;
  }

  String? optionalString(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value == null) return null;
    if (value is! String) {
      throw McpToolException(
        McpErrorCode.internal,
        'Argument "$key" must be a string, got ${_describe(value)}.',
      );
    }
    return value;
  }

  int? optionalInt(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value == null) return null;
    if (value is int) return value;
    throw McpToolException(
      McpErrorCode.internal,
      'Argument "$key" must be an integer, got ${_describe(value)}.',
    );
  }

  /// A required, non-empty array of non-empty strings — used for the one
  /// array-valued argument in the v0 surface, `request_host_access`'s
  /// `hostIds`.
  List<String> requireStringList(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is! List || value.isEmpty) {
      throw McpToolException(
        McpErrorCode.internal,
        'Argument "$key" must be a non-empty array of strings, got '
        '${_describe(value)}.',
      );
    }
    final result = <String>[];
    for (var i = 0; i < value.length; i++) {
      final item = value[i];
      if (item is! String || item.isEmpty) {
        throw McpToolException(
          McpErrorCode.internal,
          'Argument "$key[$i]" must be a non-empty string, got '
          '${_describe(item)}.',
        );
      }
      result.add(item);
    }
    return result;
  }

  String _describe(Object? value) {
    if (value == null) return 'null';
    try {
      return '${value.runtimeType} (${jsonEncode(value)})';
    } catch (_) {
      return '${value.runtimeType}';
    }
  }
}
