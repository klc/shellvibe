import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api_config.dart';
import 'api_exception.dart';

/// A raw HTTP request, free of JSON or auth concerns.
@immutable
final class ApiRawRequest {
  final String method;
  final Uri url;
  final Map<String, String> headers;

  /// Already-encoded request body, or null for a bodyless request.
  final String? body;

  const ApiRawRequest({
    required this.method,
    required this.url,
    this.headers = const {},
    this.body,
  });
}

/// A raw HTTP response.
@immutable
final class ApiRawResponse {
  final int statusCode;

  /// Response headers, lowercased keys.
  final Map<String, String> headers;

  /// Response body as text. Empty for a `204`-shaped reply.
  final String body;

  const ApiRawResponse({
    required this.statusCode,
    this.headers = const {},
    this.body = '',
  });

  String? header(String name) => headers[name.toLowerCase()];
}

/// The seam between [ApiClient] and the socket.
///
/// It exists so tests can answer requests without a server and without
/// implementing all of `dart:io`'s [HttpClient]. Production always uses
/// [IoApiTransport].
abstract interface class ApiTransport {
  Future<ApiRawResponse> send(ApiRawRequest request);

  /// Releases any pooled connections.
  void close();
}

/// [ApiTransport] over `dart:io`'s [HttpClient], matching the convention
/// `UpdateCheckService` already uses in this codebase.
final class IoApiTransport implements ApiTransport {
  final HttpClient _client;

  IoApiTransport({HttpClient? client})
    : _client = client ?? _createClient();

  static HttpClient _createClient() {
    final client = HttpClient()
      ..connectionTimeout = ApiConfig.connectionTimeout
      ..userAgent = 'ShellVibe';

    // The local development stack terminates TLS with Caddy's internal CA,
    // which no OS trust store knows about. Accepting it is gated on *both* a
    // debug build and a local host, and the accepted certificate is still
    // checked against that host -- a release binary has no path into this
    // branch, so a production token can never be handed to a MitM.
    if (kDebugMode && ApiConfig.isLocalDevelopmentHost) {
      final allowedHost = Uri.parse(ApiConfig.baseUrl).host;
      client.badCertificateCallback = (cert, host, port) => host == allowedHost;
    }

    return client;
  }

  @override
  Future<ApiRawResponse> send(ApiRawRequest request) async {
    final HttpClientRequest ioRequest;
    try {
      ioRequest = await _client.openUrl(request.method, request.url);
    } on SocketException catch (e) {
      throw ApiTransportException('Could not reach the server.', cause: e);
    } on HandshakeException catch (e) {
      throw ApiTransportException('TLS handshake failed.', cause: e);
    }

    request.headers.forEach(ioRequest.headers.set);

    final body = request.body;
    if (body != null) {
      final encoded = utf8.encode(body);
      ioRequest.headers.contentLength = encoded.length;
      ioRequest.add(encoded);
    }

    final HttpClientResponse ioResponse;
    try {
      ioResponse = await ioRequest.close().timeout(ApiConfig.responseTimeout);
    } on SocketException catch (e) {
      throw ApiTransportException('Connection dropped.', cause: e);
    } on HttpException catch (e) {
      throw ApiTransportException('Malformed HTTP response.', cause: e);
    } on TimeoutException catch (e) {
      throw ApiTransportException(
        'The server did not answer in time.',
        cause: e,
        timedOut: true,
      );
    }

    final headers = <String, String>{};
    ioResponse.headers.forEach((name, values) {
      if (values.isNotEmpty) headers[name.toLowerCase()] = values.first;
    });

    final text = await ioResponse.transform(utf8.decoder).join();

    return ApiRawResponse(
      statusCode: ioResponse.statusCode,
      headers: headers,
      body: text,
    );
  }

  @override
  void close() => _client.close(force: true);
}
