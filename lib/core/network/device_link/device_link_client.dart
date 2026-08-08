import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'device_link_identity.dart';
import 'device_link_protocol.dart';
import 'device_link_server.dart';

/// One candidate address from a QR payload or an mDNS result.
final class DeviceLinkEndpoint {
  final String host;
  final int port;
  final String spkiSha256Base64;

  const DeviceLinkEndpoint({
    required this.host,
    required this.port,
    required this.spkiSha256Base64,
  });

  Uri get uri =>
      Uri(scheme: 'wss', host: host, port: port, path: '/device-link');
}

/// Client that races all candidate addresses and keeps the first pinned link.
final class DeviceLinkClient {
  final Duration connectionTimeout;

  DeviceLinkClient({this.connectionTimeout = const Duration(seconds: 10)});

  Future<DeviceLinkClientConnection> connect(
    List<DeviceLinkEndpoint> endpoints,
  ) async {
    final candidates = endpoints
        .where(
          (endpoint) =>
              endpoint.host.isNotEmpty &&
              endpoint.port > 0 &&
              endpoint.port <= 65535 &&
              endpoint.spkiSha256Base64.isNotEmpty,
        )
        .toList();
    if (candidates.isEmpty) {
      throw const DeviceLinkTransportException(
        'no_endpoints',
        'No valid Device Link endpoints were supplied',
      );
    }

    final winner = Completer<DeviceLinkClientConnection>();
    final attempts = candidates
        .map(_DeviceLinkClientAttempt.new)
        .toList(growable: false);
    var remaining = candidates.length;
    final failures = <Object>[];
    final runners = <Future<void>>[];
    for (final attempt in attempts) {
      runners.add(
        _runAttempt(
          attempt,
          winner,
          failures,
          onFailure: (stack) {
            remaining--;
            if (remaining == 0 && !winner.isCompleted) {
              winner.completeError(
                DeviceLinkTransportException(
                  'connection_failed',
                  'Could not connect to any Device Link endpoint',
                  _selectMostInformativeFailure(failures),
                ),
                stack,
              );
            }
          },
        ),
      );
    }

    try {
      final connection = await winner.future.timeout(connectionTimeout);
      await _cancelAttempts(attempts);
      await Future.wait(runners);
      return connection;
    } on TimeoutException {
      await _cancelAttempts(attempts);
      await Future.wait(runners);
      throw const DeviceLinkTransportException(
        'connection_timeout',
        'Device Link connection timed out',
      );
    } catch (_) {
      await _cancelAttempts(attempts);
      await Future.wait(runners);
      rethrow;
    }
  }

  Future<DeviceLinkClientConnection> connectToQrPayload(
    DeviceLinkQrPayload payload,
  ) {
    if (!payload.expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const DeviceLinkTransportException(
        'qr_expired',
        'Device Link QR payload has expired',
      );
    }
    final hosts = <String>{...payload.addresses, payload.mdns, payload.host};
    return connect(
      hosts
          .map(
            (host) => DeviceLinkEndpoint(
              host: host,
              port: payload.port,
              spkiSha256Base64: payload.spki,
            ),
          )
          .toList(),
    );
  }

  Future<void> _runAttempt(
    _DeviceLinkClientAttempt attempt,
    Completer<DeviceLinkClientConnection> winner,
    List<Object> failures, {
    required void Function(StackTrace stack) onFailure,
  }) async {
    try {
      final connection = await _connectOne(attempt);
      if (winner.isCompleted) {
        await connection.close();
      } else {
        winner.complete(connection);
      }
    } catch (error, stack) {
      failures.add(error);
      onFailure(stack);
    }
  }

  Future<void> _cancelAttempts(List<_DeviceLinkClientAttempt> attempts) async {
    for (final attempt in attempts) {
      attempt.cancel();
    }
  }

  Future<DeviceLinkClientConnection> _connectOne(
    _DeviceLinkClientAttempt attempt,
  ) async {
    final endpoint = attempt.endpoint;
    final httpClient =
        HttpClient(context: SecurityContext(withTrustedRoots: false))
          ..connectionTimeout = connectionTimeout
          ..badCertificateCallback = (certificate, host, port) =>
              DeviceLinkIdentity.matchesSpkiPin(
                certificate.der,
                endpoint.spkiSha256Base64,
              );
    attempt.httpClient = httpClient;
    try {
      // The WebSocket owns the upgraded sink after connect.
      // ignore: close_sinks
      final socket = await WebSocket.connect(
        endpoint.uri.toString(),
        customClient: httpClient,
      ).timeout(connectionTimeout);
      socket.pingInterval = deviceLinkPingInterval;
      return DeviceLinkClientConnection._(socket, endpoint);
    } catch (error) {
      throw DeviceLinkTransportException(
        'connection_failed',
        'Device Link TLS/WebSocket connection failed',
        error,
      );
    } finally {
      attempt.httpClient = null;
      httpClient.close(force: true);
    }
  }
}

Object _selectMostInformativeFailure(List<Object> failures) {
  if (failures.isEmpty) {
    return StateError('Device Link connection attempts failed');
  }
  for (final failure in failures) {
    if (!_isTransientConnectionFailure(failure)) return failure;
  }
  return failures.first;
}

bool _isTransientConnectionFailure(Object error) {
  if (error is DeviceLinkTransportException) {
    final cause = error.cause;
    return cause != null && _isTransientConnectionFailure(cause);
  }
  return error is SocketException || error is TimeoutException;
}

/// Connection boundary consumed by the linked-session presentation layer.
///
/// Keeping this narrow interface separate from the WebSocket implementation
/// makes the terminal lifecycle testable without a platform HTTP binding and
/// leaves room for a reconnecting client in Phase 5.
abstract interface class DeviceLinkConnection {
  Stream<DeviceLinkControlMessage> get controlMessages;
  Stream<DeviceLinkBinaryFrame> get binaryFrames;
  bool get isClosed;
  bool get isReadOnly;

  Future<void> sendAttach(DeviceLinkAttach message);
  Future<void> sendResize(DeviceLinkResize message);
  Future<void> sendDetach();
  Future<void> sendBinary(DeviceLinkBinaryFrame frame);
  Future<void> close();
}

final class _DeviceLinkClientAttempt {
  final DeviceLinkEndpoint endpoint;
  HttpClient? httpClient;

  _DeviceLinkClientAttempt(this.endpoint);

  void cancel() {
    httpClient?.close(force: true);
    httpClient = null;
  }
}

/// A pinned client-side Device Link connection.
final class DeviceLinkClientConnection implements DeviceLinkConnection {
  final WebSocket _socket;
  final DeviceLinkEndpoint endpoint;
  final StreamController<DeviceLinkControlMessage> _controls =
      StreamController<DeviceLinkControlMessage>.broadcast();
  final StreamController<DeviceLinkBinaryFrame> _binaryFrames =
      StreamController<DeviceLinkBinaryFrame>.broadcast();
  final Queue<DeviceLinkControlMessage> _pendingControls =
      Queue<DeviceLinkControlMessage>();
  final Queue<DeviceLinkBinaryFrame> _pendingBinaryFrames =
      Queue<DeviceLinkBinaryFrame>();
  Completer<DeviceLinkControlMessage>? _controlWaiter;
  Completer<DeviceLinkBinaryFrame>? _binaryWaiter;
  StreamSubscription<Object?>? _subscription;
  bool _closed = false;
  bool _readOnly = false;

  DeviceLinkClientConnection._(this._socket, this.endpoint) {
    _subscription = _socket.listen(
      _handleMessage,
      onError: (_, _) => close(),
      onDone: close,
      cancelOnError: true,
    );
  }

  @override
  Stream<DeviceLinkControlMessage> get controlMessages => _controls.stream;

  @override
  Stream<DeviceLinkBinaryFrame> get binaryFrames => _binaryFrames.stream;

  @override
  bool get isClosed => _closed;

  @override
  bool get isReadOnly => _readOnly;

  Future<void> sendControl(DeviceLinkControlMessage message) async {
    if (_closed) {
      throw const DeviceLinkTransportException(
        'connection_closed',
        'Device Link connection is closed',
      );
    }
    // WebSocket owns this sink and closes it in [close].
    // ignore: close_sinks
    _socket.add(message.encode());
  }

  /// Sends a raw text frame for protocol compatibility tests.
  ///
  /// Production callers should use [sendControl] so outbound messages are
  /// typed and versioned by the protocol model.
  Future<void> sendRawText(String text) async {
    if (_closed) {
      throw const DeviceLinkTransportException(
        'connection_closed',
        'Device Link connection is closed',
      );
    }
    // WebSocket owns this sink and closes it in [close].
    // ignore: close_sinks
    _socket.add(text);
  }

  @override
  Future<void> sendBinary(DeviceLinkBinaryFrame frame) async {
    if (_closed) {
      throw const DeviceLinkTransportException(
        'connection_closed',
        'Device Link connection is closed',
      );
    }
    if (_readOnly) {
      throw const DeviceLinkTransportException(
        'session_reclaimed',
        'Desktop control has been reclaimed for this Device Link session',
      );
    }
    // WebSocket owns this sink and closes it in [close].
    // ignore: close_sinks
    _socket.add(frame.encode());
  }

  Future<void> sendHello(DeviceLinkHello message) => sendControl(message);

  Future<void> sendPair(DeviceLinkPair message) => sendControl(message);

  @override
  Future<void> sendAttach(DeviceLinkAttach message) => sendControl(message);

  @override
  Future<void> sendResize(DeviceLinkResize message) => sendControl(message);

  @override
  Future<void> sendDetach() => sendControl(const DeviceLinkDetach());

  Future<DeviceLinkControlMessage> nextControl({
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (_pendingControls.isNotEmpty) {
      return Future<DeviceLinkControlMessage>.value(
        _pendingControls.removeFirst(),
      );
    }
    if (_controlWaiter != null) {
      throw StateError('A Device Link control message is already awaited');
    }
    final waiter = Completer<DeviceLinkControlMessage>();
    _controlWaiter = waiter;
    return waiter.future.timeout(
      timeout,
      onTimeout: () {
        if (identical(_controlWaiter, waiter)) _controlWaiter = null;
        throw TimeoutException('Timed out waiting for a Device Link control');
      },
    );
  }

  Future<DeviceLinkBinaryFrame> nextBinary({
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (_pendingBinaryFrames.isNotEmpty) {
      return Future<DeviceLinkBinaryFrame>.value(
        _pendingBinaryFrames.removeFirst(),
      );
    }
    if (_binaryWaiter != null) {
      throw StateError('A Device Link binary frame is already awaited');
    }
    final waiter = Completer<DeviceLinkBinaryFrame>();
    _binaryWaiter = waiter;
    return waiter.future.timeout(
      timeout,
      onTimeout: () {
        if (identical(_binaryWaiter, waiter)) _binaryWaiter = null;
        throw TimeoutException('Timed out waiting for a Device Link frame');
      },
    );
  }

  void _handleMessage(Object? message) {
    if (_closed) return;
    try {
      if (message is String) {
        final control = DeviceLinkControlMessage.decode(message);
        if (control is DeviceLinkAttached) _readOnly = false;
        if (control is DeviceLinkReclaimed) _readOnly = true;
        final waiter = _controlWaiter;
        if (waiter != null) {
          _controlWaiter = null;
          waiter.complete(control);
        } else if (_controls.hasListener) {
          _controls.add(control);
        } else {
          _pendingControls.addLast(control);
        }
      } else if (message is List<int>) {
        final frame = DeviceLinkBinaryFrame.decode(message);
        final waiter = _binaryWaiter;
        if (waiter != null) {
          _binaryWaiter = null;
          waiter.complete(frame);
        } else if (_binaryFrames.hasListener) {
          _binaryFrames.add(frame);
        } else {
          _pendingBinaryFrames.addLast(frame);
        }
      } else {
        _controls.addError(
          const DeviceLinkProtocolException(
            'invalid_frame',
            'Unsupported WebSocket frame type',
          ),
        );
      }
    } on Object catch (error, stack) {
      _controls.addError(error, stack);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    const closeError = DeviceLinkTransportException(
      'connection_closed',
      'Device Link connection is closed',
    );
    _controlWaiter?.completeError(closeError);
    _controlWaiter = null;
    _binaryWaiter?.completeError(closeError);
    _binaryWaiter = null;
    await _subscription?.cancel();
    _subscription = null;
    await _controls.close();
    await _binaryFrames.close();
    try {
      await _socket.close(WebSocketStatus.normalClosure);
    } catch (_) {}
  }
}
