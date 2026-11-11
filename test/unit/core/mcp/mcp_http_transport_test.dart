import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/mcp/mcp_http_transport.dart';
import 'package:shellvibe/core/mcp/mcp_protocol.dart';

void main() {
  test('a JsonRpcErrorException keeps its code instead of -32603', () async {
    final transport = McpHttpTransport(
      onRequest: (_, _, _) async => throw const JsonRpcErrorException(
        JsonRpcError.methodNotFound,
        'Unknown method "x".',
      ),
      authenticate: (_) async => 'client',
      startPort: 0,
    );
    final port = await transport.start();
    final client = HttpClient();
    try {
      final req = await client.post('127.0.0.1', port, '/mcp');
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer t')
        ..contentType = ContentType.json;
      req.write(jsonEncode({'jsonrpc': '2.0', 'id': 7, 'method': 'x'}));
      final res = await req.close();
      final body =
          jsonDecode(await utf8.decoder.bind(res).join())
              as Map<String, Object?>;
      final error = body['error'] as Map<String, Object?>;
      expect(body['id'], 7);
      expect(error['code'], JsonRpcError.methodNotFound);
      expect(error['message'], 'Unknown method "x".');
    } finally {
      client.close(force: true);
      await transport.stop();
    }
  });

  test('each bridge connection reaches the handler and has its own rate '
      'limit', () async {
    final seen = <String?>[];
    final transport = McpHttpTransport(
      onRequest: (_, _, connectionId) async {
        seen.add(connectionId);
        return const {};
      },
      authenticate: (_) async => 'client',
      startPort: 0,
      maxRequestsPerMinute: 1,
    );
    final port = await transport.start();
    final client = HttpClient();
    Future<int> post(String? connection) async {
      final req = await client.post('127.0.0.1', port, '/mcp');
      req.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer t')
        ..contentType = ContentType.json;
      if (connection != null) {
        req.headers.set(McpHttpTransport.connectionHeader, connection);
      }
      req.write(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'x'}));
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    }

    try {
      expect(await post('window-a'), HttpStatus.ok);
      expect(await post('window-b'), HttpStatus.ok);
      expect(await post('window-a'), HttpStatus.tooManyRequests);
      expect(seen, ['window-a', 'window-b']);
    } finally {
      client.close(force: true);
      await transport.stop();
    }
  });
}
