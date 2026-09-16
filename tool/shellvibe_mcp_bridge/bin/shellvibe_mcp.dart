// shellvibe-mcp — stdio-to-HTTP bridge.
//
// An MCP client (an AI agent's tool runner) launches this binary as a
// subprocess and speaks JSON-RPC to it over stdin/stdout, exactly like it
// would to any other local MCP server. What actually holds the MCP session
// state — the SSH connections, the session pool, the vault — lives in the
// running ShellVibe app, reachable only over localhost HTTP. This binary's
// entire job is to be the dumb pipe between the two: one JSON-RPC line in,
// one HTTP POST, one JSON-RPC line out.
//
// It is deliberately a separate, Flutter-free Dart package (see
// tool/shellvibe_mcp_bridge/pubspec.yaml) because it is compiled standalone
// with `dart compile exe` and shipped as a small native binary alongside the
// app — see tool/shellvibe_mcp_bridge/README.md for the per-platform build
// and packaging story.
//
// IMPORTANT: stdout is the JSON-RPC wire. From the moment this process
// starts, nothing may ever be written to stdout except one JSON-RPC frame
// per line. Any stray print/log here would be interpreted by the MCP client
// as (or corrupt) a protocol frame. All diagnostics go to stderr, which the
// client ignores.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const int _parseErrorCode = -32700;
const int _internalErrorCode = -32603;

const String _notRunningMessage =
    'ShellVibe is not running. Open the app to reach your servers.';

// The server validates `Origin` to defend against DNS-rebinding attacks from
// a browser tab (see docs/mcp_plan.md, "HTTP sunucusu"). This bridge is not
// a browser, so it sends a fixed, non-URL value that the server allowlists
// specifically for this binary rather than a real origin it doesn't have.
const String _bridgeOrigin = 'shellvibe-bridge';

Future<void> main(List<String> arguments) async {
  final endpointPath = _resolveEndpointPath(arguments);
  final orphanWatch = _watchForOrphaning();

  // Sequential by design: the bridge is a 1:1 relay, not a scheduler. MCP
  // clients send one request and await one response before sending the
  // next in practice, and processing lines in arrival order keeps the
  // stdout stream trivially well-formed (no interleaving to reason about).
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    if (line.trim().isEmpty) {
      continue;
    }
    await _handleLine(line, endpointPath);
  }

  orphanWatch?.cancel();
}

/// Exits once this process has been orphaned, i.e. the MCP client that
/// launched it is gone.
///
/// Normally the client closing our stdin ends the loop in [main] and the
/// process exits on its own. That does not happen when the client dies
/// without closing the pipe, or when a copy of the write end was inherited by
/// something still running: stdin never reaches EOF, and the bridge sits
/// there forever. A long session that reconnects a few times then accumulates
/// one idle `shellvibe-mcp` per reconnect.
///
/// Being orphaned is the reliable signal for that: on POSIX an orphan is
/// reparented to init/launchd, so a parent pid of 1 means nobody is on the
/// other end of the pipe any more. Windows has no equivalent reparenting
/// rule, so the watch simply does not run there.
Timer? _watchForOrphaning() {
  if (!Platform.isLinux && !Platform.isMacOS) {
    return null;
  }
  return Timer.periodic(const Duration(seconds: 30), (timer) async {
    final parentPid = await _parentPid();
    // Unknown (`ps` missing or refused) is not a reason to kill a working
    // bridge; only an answer of "1" is.
    if (parentPid == 1) {
      timer.cancel();
      stderr.writeln(
        'shellvibe-mcp: parent process is gone; exiting instead of '
        'lingering.',
      );
      exit(0);
    }
  });
}

Future<int?> _parentPid() async {
  try {
    final result = await Process.run('ps', ['-o', 'ppid=', '-p', '$pid']);
    if (result.exitCode != 0) return null;
    return int.tryParse((result.stdout as String).trim());
  } catch (_) {
    return null;
  }
}

Future<void> _handleLine(String line, String endpointPath) async {
  dynamic decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException catch (e) {
    stderr.writeln('shellvibe-mcp: malformed JSON on stdin: $e');
    await _writeFrame(
      _errorFrame(id: null, code: _parseErrorCode, message: 'Parse error.'),
    );
    return;
  }

  // A JSON-RPC request must be an object; anything else parses fine as JSON
  // but isn't a request we can act on (no method, no id to reply against).
  // We fold this into "parse error" rather than adding -32600 Invalid
  // Request handling, since the bridge's scope is relaying, not validating
  // protocol shape — the app on the other end of the HTTP call is the
  // source of truth for what a valid request looks like.
  if (decoded is! Map<String, dynamic>) {
    await _writeFrame(
      _errorFrame(id: null, code: _parseErrorCode, message: 'Parse error.'),
    );
    return;
  }

  final id = decoded['id'];

  final endpoint = await _loadEndpoint(endpointPath);
  if (endpoint == null) {
    await _writeFrame(
      _errorFrame(
        id: id,
        code: _internalErrorCode,
        message: _notRunningMessage,
      ),
    );
    return;
  }

  _HttpResult result;
  try {
    result = await _postToBridge(endpoint, line);
  } catch (e) {
    // Connection refused (app not running / not listening yet), timed out,
    // or any other transport failure — from the client's point of view
    // these are all the same story: "can't reach ShellVibe right now."
    // Deliberately not fatal: the app may still be starting, or the user
    // may open it after seeing this message, and the MCP client should be
    // able to retry the *next* call without us having exited in the
    // meantime (an exited bridge gets marked permanently dead by most
    // clients).
    stderr.writeln('shellvibe-mcp: request to ShellVibe failed: $e');
    await _writeFrame(
      _errorFrame(
        id: id,
        code: _internalErrorCode,
        message: _notRunningMessage,
      ),
    );
    return;
  }

  await _writeFrame(_frameFromHttpResult(id: id, result: result));
}

/// Turns a completed HTTP response into the JSON-RPC frame to relay.
Map<String, dynamic> _frameFromHttpResult({
  required dynamic id,
  required _HttpResult result,
}) {
  dynamic body;
  try {
    body = jsonDecode(result.body);
  } on FormatException {
    body = null;
  }

  final isJsonRpcShaped =
      body is Map<String, dynamic> && body.containsKey('jsonrpc');

  if (result.statusCode >= 200 && result.statusCode < 300) {
    if (isJsonRpcShaped) {
      return body;
    }
    // The app is expected to always answer 2xx with a JSON-RPC body; if it
    // somehow doesn't, that's still "something is wrong with reaching
    // ShellVibe" from the agent's perspective, not a protocol-level error
    // worth inventing a new code for.
    return _errorFrame(
      id: id,
      code: _internalErrorCode,
      message:
          'ShellVibe returned an unexpected response (HTTP ${result.statusCode}).',
    );
  }

  // Non-2xx: pass the body through untouched if the server already gave us
  // a well-formed JSON-RPC error, otherwise wrap the HTTP status so the
  // agent gets something readable instead of a bare object it can't parse.
  if (isJsonRpcShaped) {
    return body;
  }
  return _errorFrame(
    id: id,
    code: _internalErrorCode,
    message: 'ShellVibe returned HTTP ${result.statusCode}.',
  );
}

Future<void> _writeFrame(Map<String, dynamic> frame) async {
  stdout.writeln(jsonEncode(frame));
  // The client reads line-by-line; buffered output would leave it waiting
  // on a response that already "happened" from this process's point of
  // view. Must be awaited: an unawaited flush can still be in flight when
  // the next line's write starts, and stdout's IOSink rejects overlapping
  // operations outright.
  await stdout.flush();
}

Map<String, dynamic> _errorFrame({
  required dynamic id,
  required int code,
  required String message,
}) {
  return {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}

class _HttpResult {
  const _HttpResult(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class _Endpoint {
  const _Endpoint({required this.port, required this.token});

  final int port;
  final String token;
}

/// `--endpoint <path>` (or `--endpoint=<path>`) overrides the well-known
/// location. The app needs this escape hatch on platforms where `HOME` (or
/// its equivalent) isn't a sensible place to look — e.g. a sandboxed
/// installation with a redirected profile directory — so it can hand the
/// bridge the real path explicitly instead of the bridge guessing wrong.
String _resolveEndpointPath(List<String> arguments) {
  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    if (arg == '--endpoint' && i + 1 < arguments.length) {
      return arguments[i + 1];
    }
    if (arg.startsWith('--endpoint=')) {
      return arg.substring('--endpoint='.length);
    }
  }

  // USERPROFILE is the Windows equivalent of HOME; dart:io's Platform
  // doesn't normalize this for us. If neither is set we fall through to an
  // empty path — reading it will fail like a missing file, which correctly
  // surfaces as "ShellVibe is not running" on every request rather than
  // crashing the process.
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  if (home.isEmpty) {
    return '';
  }
  return '$home${Platform.pathSeparator}.shellvibe${Platform.pathSeparator}mcp-endpoint.json';
}

Future<_Endpoint?> _loadEndpoint(String path) async {
  if (path.isEmpty) {
    return null;
  }
  try {
    final raw = await File(path).readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final port = decoded['port'];
    final token = decoded['token'];
    if (port is! int || token is! String || token.isEmpty) {
      return null;
    }
    return _Endpoint(port: port, token: token);
  } catch (e) {
    // Covers: file missing (app not running / never started with MCP on),
    // permission errors, and a malformed file (e.g. app mid-write). All of
    // these mean the same thing to the caller: we can't currently reach
    // ShellVibe, so they collapse to the same null → "not running" path.
    stderr.writeln('shellvibe-mcp: could not read endpoint file at $path: $e');
    return null;
  }
}

Future<_HttpResult> _postToBridge(_Endpoint endpoint, String rawLine) async {
  final client = HttpClient();
  // A dead app that still holds the port (or a firewall silently dropping
  // packets) would otherwise hang this request forever with the agent none
  // the wiser. A bounded wait lets us fail fast into the same "not running"
  // error instead.
  client.connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${endpoint.port}/mcp'),
    );
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${endpoint.token}',
    );
    request.headers.contentType = ContentType.json;
    request.headers.set('Origin', _bridgeOrigin);
    // Set an explicit length rather than letting HttpClient fall back to
    // chunked transfer encoding: the request bodies here are always small
    // and already fully in memory, and a known Content-Length is the more
    // conservatively compatible choice against whatever HTTP server
    // implementation ends up on the other side.
    final bytes = utf8.encode(rawLine);
    request.headers.contentLength = bytes.length;
    request.add(bytes);

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return _HttpResult(response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}
