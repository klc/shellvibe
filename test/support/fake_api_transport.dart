import 'dart:convert';

import 'package:shellvibe/core/api/api_exception.dart';
import 'package:shellvibe/core/api/api_transport.dart';

/// Scripted [ApiTransport] for tests.
///
/// Answers each request from a queue, records what was sent, and can raise a
/// transport failure so retry behaviour is testable without a socket.
final class FakeApiTransport implements ApiTransport {
  final List<ApiRawRequest> sent = [];
  final List<Object> _queue = [];

  bool closed = false;

  /// Queues an HTTP reply.
  void enqueue({
    int status = 200,
    Object? body,
    Map<String, String> headers = const {},
  }) {
    _queue.add(
      ApiRawResponse(
        statusCode: status,
        headers: {
          for (final entry in headers.entries)
            entry.key.toLowerCase(): entry.value,
        },
        body: switch (body) {
          null => '',
          final String s => s,
          _ => jsonEncode(body),
        },
      ),
    );
  }

  /// Queues a transport-level failure (no HTTP response at all).
  void enqueueTransportFailure({
    String reason = 'fake failure',
    bool timedOut = false,
  }) {
    _queue.add(ApiTransportException(reason, timedOut: timedOut));
  }

  /// Requests still queued and unanswered.
  int get pending => _queue.length;

  /// The most recent request, or null.
  ApiRawRequest? get lastRequest => sent.isEmpty ? null : sent.last;

  /// Decoded JSON body of the most recent request.
  Map<String, Object?> get lastBody {
    final body = lastRequest?.body;
    if (body == null || body.isEmpty) return const {};
    final decoded = jsonDecode(body);

    return decoded is Map<String, Object?> ? decoded : const {};
  }

  @override
  Future<ApiRawResponse> send(ApiRawRequest request) async {
    sent.add(request);

    if (_queue.isEmpty) {
      throw StateError(
        'FakeApiTransport received an unexpected ${request.method} '
        '${request.url} with nothing queued.',
      );
    }

    final next = _queue.removeAt(0);
    if (next is ApiTransportException) throw next;

    return next as ApiRawResponse;
  }

  @override
  void close() => closed = true;
}
