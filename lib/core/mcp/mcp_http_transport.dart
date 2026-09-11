import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mcp_protocol.dart';

/// Handles one already-authenticated JSON-RPC request and returns the value
/// that becomes the `result` field of the JSON-RPC response.
///
/// Any exception thrown here is caught by [McpHttpTransport] itself (see its
/// class docstring) and reported to the caller as a generic `-32603`
/// internal error — this callback never needs its own top-level try/catch to
/// keep the server alive.
typedef McpTransportRequestHandler =
    Future<Object?> Function(String clientId, JsonRpcRequest request);

/// Verifies a bearer token and returns the id of the client it belongs to,
/// or `null` if the token is missing, malformed, revoked, or expired.
typedef McpTransportAuthenticator =
    Future<String?> Function(String bearerToken);

/// Raised by [McpHttpTransport.start] when no free loopback port could be
/// found within [McpHttpTransport.maxPortAttempts] tries.
class McpHttpTransportStartException implements Exception {
  final String message;
  const McpHttpTransportStartException(this.message);

  @override
  String toString() => 'McpHttpTransportStartException: $message';
}

/// The localhost HTTP transport for the MCP server: `POST /mcp` for
/// JSON-RPC requests/notifications, `GET /mcp` for a server→client
/// Server-Sent Events stream.
///
/// This is the `dart:io` `HttpServer` sibling of
/// `core/network/device_link/device_link_server.dart` — same house pattern
/// (bind, `listen`, per-request try/catch so one bad request can never take
/// the listener down) — but deliberately does **not** reuse that file's
/// shape verbatim: Device Link is a TLS **WebSocket** server that binds
/// `InternetAddress.anyIPv4` by design (a phone on the LAN has to reach it).
/// MCP is the opposite: a plaintext HTTP server that must be reachable from
/// nowhere but this machine, because the only thing standing between an
/// agent process and a user's SSH credentials is "you have to already be
/// running as this OS user to hold the bearer token" — see
/// `mcp_endpoint_file.dart`. Loopback-only binding is what makes that true.
///
/// **Loopback-only, no exceptions.** [start] binds exclusively to
/// [InternetAddress.loopbackIPv4] (`127.0.0.1`). There is no constructor
/// parameter, no setting, and no code path anywhere in this class that can
/// bind `InternetAddress.anyIPv4` (`0.0.0.0`) or any other interface — the
/// bind address is not configurable at all, on purpose. Binding to any
/// non-loopback interface would put a bearer-token-gated shell/SSH gateway
/// on the LAN (or the open internet, on a misconfigured host), which no
/// setting should ever be able to do by accident.
///
/// **Origin validation is mandatory, not optional.** Every request's
/// `Origin` header (see [_originAllowed]) is checked before anything else
/// runs, including authentication. This defends against DNS rebinding: a
/// malicious web page cannot itself connect to `127.0.0.1`, but it CAN get
/// the *victim's browser* to do so, by first resolving a DNS name it
/// controls to a public IP (passing the browser's same-origin checks at
/// fetch time) and then re-pointing that same name to `127.0.0.1` for the
/// actual TCP connection. The browser still attaches the page's real
/// `Origin` header to the request, though — a header the bridge/CLI clients
/// this server is meant to talk to never send a *browser* origin for in the
/// first place. Rejecting any `Origin` that is not our own reserved marker
/// closes that hole without needing CORS or TLS on a loopback socket.
final class McpHttpTransport {
  /// Handles authenticated requests. See [McpTransportRequestHandler].
  final McpTransportRequestHandler onRequest;

  /// Verifies bearer tokens. See [McpTransportAuthenticator].
  final McpTransportAuthenticator authenticate;

  /// First port [start] tries. Never hard-coded elsewhere — every caller
  /// that needs "the" MCP port must read it back from [port] after [start]
  /// returns, never assume this value is the one actually bound.
  final int startPort;

  /// Requests allowed per client id per rolling minute before `429`.
  final int maxRequestsPerMinute;

  /// Upper bound on how many ports [start] will try (`startPort`,
  /// `startPort + 1`, ...) before giving up. Twenty is generous headroom for
  /// "something else is squatting on 7433" while still failing fast instead
  /// of scanning thousands of ports on a broken machine.
  static const int maxPortAttempts = 20;

  /// Length of the fixed rate-limit window. A fixed window (reset the count
  /// to zero every 60s) was chosen over a sliding one because a client
  /// bursting right at the window boundary is a tolerable failure mode for a
  /// *local* agent tool-calling loop — it is not defending against a remote
  /// attacker who would pick that boundary on purpose, only against a buggy
  /// or looping agent, and a fixed window is one field per client instead of
  /// a timestamp deque.
  static const Duration _rateLimitWindow = Duration(minutes: 1);

  /// The only origin value this transport accepts from a real, non-browser
  /// client. Deliberately not a URL (`http://...`) — a genuine browser
  /// origin is exactly what a DNS-rebinding page WOULD send, so accepting
  /// any browser-shaped origin here would defeat the point. Clients speaking
  /// to this server (the `shellvibe-mcp` stdio bridge, tests, ...) set this
  /// literal string themselves.
  static const String _allowedOrigin = 'shellvibe-bridge';

  /// Implementation-defined JSON-RPC error codes in the `-32000`..`-32099`
  /// "server error" range the spec reserves for transport-specific use.
  /// These three failures are detected by this transport itself, before a
  /// request ever reaches [onRequest] — they describe the HTTP/auth layer,
  /// not an MCP method outcome, so they do not belong to the standard
  /// `JsonRpcError` codes.
  static const int _originForbiddenCode = -32000;
  static const int _unauthorizedCode = -32001;
  static const int _rateLimitedCode = -32002;

  HttpServer? _httpServer;
  final Set<HttpResponse> _sseClients = {};
  final Map<String, _RateWindow> _rateWindows = {};

  McpHttpTransport({
    required this.onRequest,
    required this.authenticate,
    this.startPort = 7433,
    this.maxRequestsPerMinute = 120,
  });

  bool get isRunning => _httpServer != null;

  /// The bound port, or `null` before [start] / after [stop].
  int? get port => _httpServer?.port;

  /// Binds the server to the first free loopback port at or after
  /// [startPort] and starts accepting connections. Returns the bound port.
  ///
  /// Calling [start] while already running is a no-op that returns the
  /// existing [port] — callers do not need to check [isRunning] themselves.
  Future<int> start() async {
    final runningServer = _httpServer;
    if (runningServer != null) return runningServer.port;

    HttpServer? bound;
    for (var attempt = 0; attempt < maxPortAttempts; attempt++) {
      final candidate = startPort + attempt;
      try {
        bound = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          candidate,
          shared: false,
        );
        break;
      } on SocketException {
        // Port taken (by us in a previous run that hasn't released it yet,
        // or by something unrelated) — try the next one.
        continue;
      }
    }

    if (bound == null) {
      throw McpHttpTransportStartException(
        'Could not bind the MCP HTTP server to a free loopback port in the '
        'range $startPort-${startPort + maxPortAttempts - 1}',
      );
    }

    _httpServer = bound;
    bound.listen(
      _handleRequest,
      onError: (Object error, StackTrace stackTrace) {
        stderr.writeln('McpHttpTransport: listener error: $error\n$stackTrace');
      },
    );
    return bound.port;
  }

  /// Stops accepting connections, force-closes every open SSE stream, and
  /// releases the port. Safe to call when not running.
  Future<void> stop() async {
    final server = _httpServer;
    if (server == null) return;
    _httpServer = null;

    for (final client in List<HttpResponse>.of(_sseClients)) {
      try {
        await client.close();
      } on Object {
        // The client may already be gone; nothing to clean up beyond
        // removing it below.
      }
    }
    _sseClients.clear();
    _rateWindows.clear();

    // `force: true` drops any request still mid-flight rather than waiting
    // for it to finish — the caller of `stop` (the vault-lock path, in
    // particular) needs "no more MCP activity" to be true the moment this
    // future completes, not "eventually, once whatever was running wraps up".
    await server.close(force: true);
  }

  /// Pushes [notification] to every currently connected `GET /mcp` SSE
  /// client. Dead subscriptions (the peer went away without a clean
  /// close — e.g. the bridge process was killed) are pruned as they are
  /// discovered rather than on a timer, since a write is the only reliable
  /// way to notice one on a plain `HttpResponse`.
  void broadcastNotification(JsonRpcNotification notification) {
    if (_sseClients.isEmpty) return;
    final frame = 'data: ${jsonEncode(notification.toJson())}\n\n';
    for (final client in List<HttpResponse>.of(_sseClients)) {
      try {
        client.write(frame);
      } on Object {
        _sseClients.remove(client);
      }
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (!_originAllowed(request)) {
        await _respondError(
          request,
          HttpStatus.forbidden,
          const JsonRpcError(
            code: _originForbiddenCode,
            message: 'Origin header is not permitted to reach the MCP server',
          ),
        );
        return;
      }

      if (request.uri.path != '/mcp') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      switch (request.method) {
        case 'POST':
          await _handlePost(request);
        case 'GET':
          await _handleGet(request);
        default:
          request.response.statusCode = HttpStatus.methodNotAllowed;
          await request.response.close();
      }
    } on Object catch (error, stackTrace) {
      // This is the backstop for the whole request lifecycle: nothing above
      // — origin/auth checks, body parsing, [onRequest] itself — may ever
      // let an exception escape and kill the server's `listen` loop.
      stderr.writeln(
        'McpHttpTransport: unhandled error on ${request.method} '
        '${request.uri.path}: $error\n$stackTrace',
      );
      try {
        await _respondError(
          request,
          HttpStatus.internalServerError,
          const JsonRpcError(
            code: JsonRpcError.internalError,
            message: 'Internal error handling request',
          ),
        );
      } on Object {
        // The response may already be closed/broken; there is nothing left
        // to do but drop it.
      }
    }
  }

  /// Blocks DNS rebinding — see the class docstring. `null`/empty is
  /// deliberately accepted: non-browser HTTP clients (the stdio bridge,
  /// `curl`, tests) routinely send no `Origin` header at all, and that is
  /// exactly the traffic this server exists to serve. What must never pass
  /// is a header present with any value other than our own marker, because
  /// that is what a browser-driven request — legitimate or rebound — looks
  /// like.
  bool _originAllowed(HttpRequest request) {
    final origin = request.headers.value('origin');
    if (origin == null || origin.isEmpty) return true;
    return origin == _allowedOrigin;
  }

  String? _bearerToken(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null) return null;
    const prefix = 'Bearer ';
    if (!header.startsWith(prefix)) return null;
    final token = header.substring(prefix.length).trim();
    return token.isEmpty ? null : token;
  }

  /// Authenticates and rate-limits [request], writing the appropriate `401`
  /// or `429` (plus a JSON-RPC error body naming the problem) and returning
  /// `null` if either check fails. Shared by `POST` and `GET` since both
  /// require a bearer token.
  Future<String?> _authenticateAndRateLimit(HttpRequest request) async {
    final token = _bearerToken(request);
    if (token == null) {
      await _respondError(
        request,
        HttpStatus.unauthorized,
        const JsonRpcError(
          code: _unauthorizedCode,
          message:
              'Missing or malformed "Authorization: Bearer <token>" header',
        ),
      );
      return null;
    }

    final clientId = await authenticate(token);
    if (clientId == null) {
      await _respondError(
        request,
        HttpStatus.unauthorized,
        const JsonRpcError(
          code: _unauthorizedCode,
          message: 'Bearer token is invalid, revoked, or expired',
        ),
      );
      return null;
    }

    if (!_admitRequest(clientId)) {
      await _respondError(
        request,
        HttpStatus.tooManyRequests,
        JsonRpcError(
          code: _rateLimitedCode,
          message:
              'Client "$clientId" exceeded $maxRequestsPerMinute requests/minute',
        ),
      );
      return null;
    }

    return clientId;
  }

  bool _admitRequest(String clientId) {
    final now = DateTime.now();
    final window = _rateWindows.putIfAbsent(clientId, () => _RateWindow(now));
    if (now.difference(window.start) >= _rateLimitWindow) {
      window.start = now;
      window.count = 0;
    }
    window.count += 1;
    return window.count <= maxRequestsPerMinute;
  }

  Future<void> _handlePost(HttpRequest request) async {
    final clientId = await _authenticateAndRateLimit(request);
    if (clientId == null) return;

    final String raw;
    try {
      raw = await utf8.decoder.bind(request).join();
    } on Object {
      await _respondError(
        request,
        HttpStatus.badRequest,
        const JsonRpcError(
          code: JsonRpcError.parseError,
          message: 'Could not read the request body',
        ),
      );
      return;
    }

    final JsonRpcMessage message;
    try {
      message = JsonRpcMessage.parse(raw);
    } on McpProtocolException catch (error) {
      await _respondError(
        request,
        HttpStatus.badRequest,
        JsonRpcError(
          code: error.code == 'parse_error'
              ? JsonRpcError.parseError
              : JsonRpcError.invalidRequest,
          message: error.message,
        ),
      );
      return;
    }

    switch (message) {
      case JsonRpcNotification():
        // Fire-and-acknowledge per the MCP Streamable HTTP transport: a
        // notification has no id to reply to, so the only meaningful
        // response is "received", not a result.
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();

      case JsonRpcRequest():
        Object? result;
        try {
          result = await onRequest(clientId, message);
        } on Object catch (error, stackTrace) {
          stderr.writeln(
            'McpHttpTransport: onRequest threw for method '
            '"${message.method}" (client $clientId): $error\n$stackTrace',
          );
          await _respondJson(
            request,
            HttpStatus.ok,
            JsonRpcError(
              id: message.id,
              code: JsonRpcError.internalError,
              message: 'Internal error handling request',
            ).toJson(),
          );
          return;
        }
        await _respondJson(
          request,
          HttpStatus.ok,
          JsonRpcResponse(id: message.id, result: result).toJson(),
        );

      case JsonRpcResponse():
      case JsonRpcError():
        // This server never sends server-initiated requests in v0, so a
        // peer has nothing of ours to reply to.
        await _respondError(
          request,
          HttpStatus.badRequest,
          const JsonRpcError(
            code: JsonRpcError.invalidRequest,
            message:
                'POST /mcp only accepts JSON-RPC requests and notifications',
          ),
        );
    }
  }

  /// Opens a long-lived `text/event-stream` response and registers it for
  /// [broadcastNotification]. The response is deliberately never closed
  /// here — it stays open until the peer disconnects (removed via
  /// [HttpResponse.done]) or [stop] force-closes it.
  Future<void> _handleGet(HttpRequest request) async {
    final clientId = await _authenticateAndRateLimit(request);
    if (clientId == null) return;

    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.bufferOutput = false;
    response.headers
      ..set(HttpHeaders.contentTypeHeader, 'text/event-stream')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set(HttpHeaders.connectionHeader, 'keep-alive');

    _sseClients.add(response);
    unawaited(
      response.done
          .then((_) => _sseClients.remove(response))
          .catchError((_) => _sseClients.remove(response)),
    );
  }

  Future<void> _respondJson(
    HttpRequest request,
    int statusCode,
    Map<String, Object?> body,
  ) async {
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _respondError(
    HttpRequest request,
    int statusCode,
    JsonRpcError error,
  ) => _respondJson(request, statusCode, error.toJson());
}

class _RateWindow {
  DateTime start;
  int count = 0;
  _RateWindow(this.start);
}
