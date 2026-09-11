import 'dart:convert';

/// Protocol version this server negotiates in `initialize`.
///
/// v0 speaks exactly one MCP protocol revision. Multi-version negotiation is
/// deferred until a real client forces the question; until then a mismatched
/// request gets a precise rejection instead of a server that silently
/// half-understands a newer or older wire shape.
const String kMcpProtocolVersion = '2025-06-18';

/// Raised when an MCP frame is malformed or violates protocol rules.
class McpProtocolException implements Exception {
  final String code;
  final String message;

  const McpProtocolException(this.code, this.message);

  @override
  String toString() => 'McpProtocolException($code): $message';
}

/// Raised when a peer's `initialize` request declares a protocol version
/// this server does not speak.
class McpUnsupportedVersionException extends McpProtocolException {
  final String version;

  const McpUnsupportedVersionException(this.version)
    : super('unsupported_version', 'Unsupported MCP protocol version');
}

/// Checks an `initialize` request's declared `protocolVersion` against the
/// one version this server speaks.
///
/// Kept as a free function rather than folded into a session/handler class:
/// this file is pure protocol, no session state, so the check that guards
/// entry into a session lives here as the one place both the transport and
/// any future test can call it without pulling in the rest of the server.
String negotiateMcpProtocolVersion(String requested) {
  if (requested != kMcpProtocolVersion) {
    throw McpUnsupportedVersionException(requested);
  }
  return requested;
}

/// Base class for JSON-RPC 2.0 frames exchanged over the MCP transport.
///
/// MCP layers its own methods (`initialize`, `tools/list`, ...) on top of
/// plain JSON-RPC 2.0 framing, so this envelope carries no MCP-specific
/// knowledge — it only has to tell a request from a notification from a
/// response from an error, per the JSON-RPC spec's own rules for which keys
/// appear together.
sealed class JsonRpcMessage {
  const JsonRpcMessage();

  Map<String, Object?> toJson();

  String encode() => jsonEncode(toJson());

  static JsonRpcMessage parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const McpProtocolException(
        'parse_error',
        'Frame is not valid JSON',
      );
    }
    return fromJson(decoded);
  }

  /// Distinguishes request/notification/response/error by which keys are
  /// present, mirroring the JSON-RPC 2.0 spec rather than trusting a
  /// self-declared frame type — the wire format has no such field, so this
  /// is the only correct way to route it. Never lets a malformed frame
  /// escape as a raw `TypeError` from an unchecked cast.
  static JsonRpcMessage fromJson(Object? value) {
    final object = _asObject(value);

    if (object['jsonrpc'] != '2.0') {
      throw const McpProtocolException(
        'invalid_request',
        'Frame is missing "jsonrpc": "2.0"',
      );
    }

    if (object.containsKey('error')) {
      return JsonRpcError._fromJsonObject(object);
    }
    if (object.containsKey('method')) {
      return object.containsKey('id') && object['id'] != null
          ? JsonRpcRequest._fromJsonObject(object)
          : JsonRpcNotification._fromJsonObject(object);
    }
    if (object.containsKey('result')) {
      return JsonRpcResponse._fromJsonObject(object);
    }
    throw const McpProtocolException(
      'invalid_request',
      'Frame has none of "method", "result", or "error"',
    );
  }
}

/// A call that expects a matching response, identified by [id].
final class JsonRpcRequest extends JsonRpcMessage {
  final Object id;
  final String method;
  final Map<String, Object?> params;

  const JsonRpcRequest({
    required this.id,
    required this.method,
    this.params = const {},
  });

  @override
  Map<String, Object?> toJson() => {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    if (params.isNotEmpty) 'params': params,
  };

  static JsonRpcRequest _fromJsonObject(Map<String, Object?> object) {
    return JsonRpcRequest(
      id: _requiredId(object),
      method: _requiredString(object, 'method'),
      params: _optionalParams(object),
    );
  }
}

/// A call that expects no response — MCP uses this for
/// `notifications/initialized` and other fire-and-forget signals.
final class JsonRpcNotification extends JsonRpcMessage {
  final String method;
  final Map<String, Object?> params;

  const JsonRpcNotification({required this.method, this.params = const {}});

  @override
  Map<String, Object?> toJson() => {
    'jsonrpc': '2.0',
    'method': method,
    if (params.isNotEmpty) 'params': params,
  };

  static JsonRpcNotification _fromJsonObject(Map<String, Object?> object) {
    return JsonRpcNotification(
      method: _requiredString(object, 'method'),
      params: _optionalParams(object),
    );
  }
}

/// A successful reply to a [JsonRpcRequest]. [result] may legitimately be
/// `null` — that is a valid JSON-RPC result, distinct from an absent field.
final class JsonRpcResponse extends JsonRpcMessage {
  final Object id;
  final Object? result;

  const JsonRpcResponse({required this.id, this.result});

  @override
  Map<String, Object?> toJson() => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  static JsonRpcResponse _fromJsonObject(Map<String, Object?> object) {
    return JsonRpcResponse(id: _requiredId(object), result: object['result']);
  }
}

/// A failed reply to a [JsonRpcRequest].
///
/// [id] is nullable per the JSON-RPC spec: a request that failed before its
/// id could even be read (e.g. `parse_error` on unparseable JSON) reports
/// `id: null` because there is no id to echo back.
final class JsonRpcError extends JsonRpcMessage {
  /// Standard JSON-RPC 2.0 reserved error codes.
  static const int parseError = -32700;
  static const int invalidRequest = -32600;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int internalError = -32603;

  final Object? id;
  final int code;
  final String message;
  final Object? data;

  const JsonRpcError({
    this.id,
    required this.code,
    required this.message,
    this.data,
  });

  @override
  Map<String, Object?> toJson() => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message, if (data != null) 'data': data},
  };

  static JsonRpcError _fromJsonObject(Map<String, Object?> object) {
    final rawError = object['error'];
    if (rawError is! Map) {
      throw const McpProtocolException(
        'invalid_request',
        'Field "error" must be an object',
      );
    }
    final errorObject = rawError.map(
      (key, nested) => MapEntry(key as String, nested),
    );
    return JsonRpcError(
      id: _optionalId(object),
      code: _requiredInt(errorObject, 'code'),
      message: _requiredString(errorObject, 'message'),
      data: errorObject['data'],
    );
  }
}

/// Identity a server reports in `initialize`'s result.
class McpServerInfo {
  final String name;
  final String version;

  const McpServerInfo({required this.name, required this.version});

  Map<String, Object?> toJson() => {'name': name, 'version': version};
}

/// Result payload for the `initialize` method.
///
/// [capabilities] only ever advertises `tools` for v0 — no `resources` or
/// `prompts`, per `docs/mcp_plan.md`'s explicit v0 slice. Advertising a
/// capability this server doesn't implement yet would let a client attempt
/// `resources/list` and get a confusing `methodNotFound` instead of never
/// trying in the first place.
class McpInitializeResult {
  final String protocolVersion;
  final McpServerInfo serverInfo;
  final Map<String, Object?> capabilities;

  McpInitializeResult({
    required this.serverInfo,
    this.protocolVersion = kMcpProtocolVersion,
    Map<String, Object?>? capabilities,
  }) : capabilities =
           capabilities ??
           const {
             'tools': {'listChanged': true},
           };

  Map<String, Object?> toJson() => {
    'protocolVersion': protocolVersion,
    'serverInfo': serverInfo.toJson(),
    'capabilities': capabilities,
  };
}

/// One entry in a `tools/list` response, describing a callable tool and the
/// JSON Schema its arguments must satisfy.
class McpToolDefinition {
  final String name;
  final String description;
  final Map<String, Object?> inputSchema;

  const McpToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'inputSchema': inputSchema,
  };
}

/// The result of a `tools/call`.
///
/// MCP has no typed "structured result" field — every tool result is a list
/// of content blocks meant for a model to read, so a structured payload
/// (a host list, a command's stdout/exit code, ...) has to be JSON-encoded
/// into a single text block rather than returned as its own JSON value.
/// [isError] is the protocol's one piece of out-of-band signal: handlers
/// should set it instead of embedding an `"error"` key inside the encoded
/// payload, so a client can tell "the tool ran and reports failure" apart
/// from "the tool's own result data happens to contain that key".
class McpToolResult {
  final List<Map<String, Object?>> content;
  final bool isError;

  const McpToolResult({required this.content, this.isError = false});

  factory McpToolResult.json(Object? value) {
    return McpToolResult(content: [_textBlock(jsonEncode(value))]);
  }

  factory McpToolResult.error(String text) {
    return McpToolResult(content: [_textBlock(text)], isError: true);
  }

  Map<String, Object?> toJson() => {'content': content, 'isError': isError};

  static Map<String, Object?> _textBlock(String text) => {
    'type': 'text',
    'text': text,
  };
}

/// Method names this server's v0 surface handles.
abstract final class McpMethod {
  static const String initialize = 'initialize';
  static const String initialized = 'notifications/initialized';
  static const String toolsList = 'tools/list';
  static const String toolsCall = 'tools/call';
  static const String ping = 'ping';
}

Map<String, Object?> _asObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return value.map((key, nested) => MapEntry(key, nested));
  }
  if (value is Map<String, Object?>) return value;
  throw const McpProtocolException(
    'invalid_request',
    'Frame must be a JSON object',
  );
}

Object _field(Map<String, Object?> object, String name) {
  if (!object.containsKey(name) || object[name] == null) {
    throw McpProtocolException(
      'invalid_request',
      'Missing required field: $name',
    );
  }
  return object[name] as Object;
}

String _requiredString(Map<String, Object?> object, String name) {
  final value = _field(object, name);
  if (value is! String || value.isEmpty) {
    throw McpProtocolException(
      'invalid_request',
      'Field $name must be a non-empty string',
    );
  }
  return value;
}

int _requiredInt(Map<String, Object?> object, String name) {
  final value = _field(object, name);
  if (value is! int) {
    throw McpProtocolException(
      'invalid_request',
      'Field $name must be an integer',
    );
  }
  return value;
}

Object _requiredId(Map<String, Object?> object) {
  final value = _field(object, 'id');
  if (value is! String && value is! int) {
    throw const McpProtocolException(
      'invalid_request',
      'Field id must be a string or integer',
    );
  }
  return value;
}

Object? _optionalId(Map<String, Object?> object) {
  if (!object.containsKey('id') || object['id'] == null) return null;
  final value = object['id'];
  if (value is! String && value is! int) {
    throw const McpProtocolException(
      'invalid_request',
      'Field id must be a string, integer, or null',
    );
  }
  return value;
}

Map<String, Object?> _optionalParams(Map<String, Object?> object) {
  if (!object.containsKey('params') || object['params'] == null) {
    return const {};
  }
  final value = object['params'];
  if (value is! Map) {
    throw const McpProtocolException(
      'invalid_params',
      'Field params must be an object',
    );
  }
  return value.map((key, nested) => MapEntry(key as String, nested));
}
