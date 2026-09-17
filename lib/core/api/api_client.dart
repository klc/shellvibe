import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'api_response.dart';
import 'api_transport.dart';

/// Supplies the current bearer token, or null when signed out.
typedef ApiTokenProvider = Future<String?> Function();

/// Called when the server rejects the stored token, so the session layer can
/// drop it without the client depending on storage.
typedef ApiUnauthenticatedCallback = Future<void> Function();

/// JSON client for the ShellVibe Server v1 API.
///
/// Responsibilities kept here and nowhere else: bearer auth, JSON encode and
/// decode, mapping the contract error body onto [ApiException], reading rate
/// limit metadata, and one retry for idempotent reads. Everything about *what*
/// the endpoints mean belongs to the feature repositories that call this.
///
/// Deliberately absent: an `X-Request-ID` on the way out. The contract lets a
/// client send one, but the server refuses to make a security decision on the
/// client's value and generates its own anyway, so sending one buys nothing and
/// risks colliding with the id the server logs. Requests are correlated by the
/// id that comes *back*.
final class ApiClient {
  final ApiTransport _transport;

  /// Supplies the bearer token for authenticated calls.
  final ApiTokenProvider? tokenProvider;

  /// Invoked when the server rejects the token.
  final ApiUnauthenticatedCallback? onUnauthenticated;

  ApiClient({
    ApiTransport? transport,
    this.tokenProvider,
    this.onUnauthenticated,
  }) : _transport = transport ?? IoApiTransport() {
    assert(
      ApiConfig.baseUrl.startsWith('https://') ||
          ApiConfig.isLocalDevelopmentHost,
      'A non-local API base URL must be HTTPS: ${ApiConfig.baseUrl}',
    );
  }

  /// GET, retried once on a transport failure because a read has no side
  /// effects to duplicate.
  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) => _sendWithRetry(
    method: 'GET',
    path: path,
    query: query,
    authenticated: authenticated,
  );

  /// POST. Never retried: whether the server applied it is unknown, and only
  /// endpoints carrying their own idempotency key (`upload_id`, `upload`-style
  /// tokens) may be re-sent, which is the caller's decision to make.
  Future<ApiResponse> post(
    String path, {
    Object? body,
    bool authenticated = true,
  }) => _send(
    method: 'POST',
    path: path,
    body: body,
    authenticated: authenticated,
  );

  /// PUT. Not retried, for the same reason as [post].
  Future<ApiResponse> put(
    String path, {
    Object? body,
    bool authenticated = true,
  }) => _send(
    method: 'PUT',
    path: path,
    body: body,
    authenticated: authenticated,
  );

  /// PATCH. Not retried, for the same reason as [post].
  Future<ApiResponse> patch(
    String path, {
    Object? body,
    bool authenticated = true,
  }) => _send(
    method: 'PATCH',
    path: path,
    body: body,
    authenticated: authenticated,
  );

  /// DELETE. Not retried, for the same reason as [post].
  Future<ApiResponse> delete(
    String path, {
    Object? body,
    bool authenticated = true,
  }) => _send(
    method: 'DELETE',
    path: path,
    body: body,
    authenticated: authenticated,
  );

  /// Releases pooled connections. Call on app teardown.
  void close() => _transport.close();

  Future<ApiResponse> _sendWithRetry({
    required String method,
    required String path,
    Map<String, String>? query,
    Object? body,
    required bool authenticated,
  }) async {
    try {
      return await _send(
        method: method,
        path: path,
        query: query,
        body: body,
        authenticated: authenticated,
      );
    } on ApiTransportException {
      return _send(
        method: method,
        path: path,
        query: query,
        body: body,
        authenticated: authenticated,
      );
    }
  }

  Future<ApiResponse> _send({
    required String method,
    required String path,
    Map<String, String>? query,
    Object? body,
    required bool authenticated,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};

    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    if (authenticated) {
      final token = await tokenProvider?.call();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          statusCode: 401,
          code: ApiErrorCode.unauthenticated,
          message: 'No account session on this device.',
        );
      }
      headers['Authorization'] = 'Bearer $token';
    }

    final raw = await _transport.send(
      ApiRawRequest(
        method: method,
        url: ApiConfig.resolve(path, query: query),
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      ),
    );

    final requestId = raw.header('x-request-id');
    final decoded = _decodeBody(raw.body);

    if (raw.statusCode >= 200 && raw.statusCode < 300) {
      return ApiResponse(
        statusCode: raw.statusCode,
        requestId: requestId,
        data: decoded?['data'],
        meta: _asJsonMap(decoded?['meta']),
      );
    }

    final failure = ApiException(
      statusCode: raw.statusCode,
      code: _readCode(decoded),
      message: _readMessage(decoded, raw.statusCode),
      details: _asJsonMap(decoded?['details']),
      // A body-level request_id is the same value as the header, but a proxy
      // error page has neither, so try both before giving up.
      requestId: requestId ?? _readString(decoded?['request_id']),
      retryAfterSeconds: int.tryParse(raw.header('retry-after') ?? ''),
    );

    if (failure.isUnauthenticated) {
      await onUnauthenticated?.call();
    }

    throw failure;
  }

  /// Decodes a JSON object body, or null when the body is empty or is not an
  /// object. A non-JSON body means something other than the API answered --
  /// a proxy or a captive portal -- and is treated as "no contract fields".
  Map<String, Object?>? _decodeBody(String body) {
    if (body.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(body);

      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException catch (e) {
      if (kDebugMode) {
        debugPrint('ApiClient: response body was not JSON: $e');
      }

      return null;
    }
  }

  static String _readCode(Map<String, Object?>? body) {
    final code = _readString(body?['code']);

    return (code == null || code.isEmpty) ? ApiErrorCode.unknown : code;
  }

  static String _readMessage(Map<String, Object?>? body, int statusCode) {
    final message = _readString(body?['message']);

    return (message == null || message.isEmpty)
        ? 'The server answered $statusCode without a contract error body.'
        : message;
  }

  static String? _readString(Object? value) => value is String ? value : null;

  static Map<String, Object?> _asJsonMap(Object? value) =>
      value is Map<String, Object?> ? value : const {};
}
