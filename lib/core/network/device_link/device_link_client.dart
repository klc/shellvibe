import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

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
      // An attempt that won the race in the same turn the timeout fired left a
      // live socket in a completer nobody will ever await.
      if (winner.isCompleted) {
        unawaited(
          winner.future
              .then((connection) => connection.close())
              .catchError((Object _) {}),
        );
      }
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
      // `attempt.cancel()` cannot reach a connection that finished while the
      // race was being torn down: `_connectOne` has already dropped the
      // HttpClient the attempt held. So an attempt that lands after the race
      // is over closes its own socket, whether it lost or the race timed out.
      if (winner.isCompleted || attempt.isCancelled) {
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
  bool _cancelled = false;

  _DeviceLinkClientAttempt(this.endpoint);

  /// True once the race no longer wants this attempt's result, whether it was
  /// won by another endpoint or abandoned on timeout.
  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    httpClient?.close(force: true);
    httpClient = null;
  }
}

/// A pinned client-side Device Link connection.
final class DeviceLinkClientConnection implements DeviceLinkConnection {
  static const _closedError = DeviceLinkTransportException(
    'connection_closed',
    'Device Link connection is closed',
  );
  final WebSocket _socket;
  final DeviceLinkEndpoint endpoint;
  late final StreamController<DeviceLinkControlMessage> _controls =
      StreamController<DeviceLinkControlMessage>.broadcast(
        onListen: _drainControls,
      );
  late final StreamController<DeviceLinkBinaryFrame> _binaryFrames =
      StreamController<DeviceLinkBinaryFrame>.broadcast(
        onListen: _drainBinaryFrames,
      );
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

  /// Hands a control message to whoever is waiting for one, or holds it.
  ///
  /// Messages that arrive while nobody is listening are queued rather than
  /// dropped: the pairing flow leaves the socket unattended across the session
  /// picker and the first frame of the linked screen, and an `attached` or an
  /// `error` landing in that gap is exactly what decides the phone's next move.
  /// Queueing then draining on subscribe keeps them, in arrival order — a new
  /// message joins the back of the queue rather than overtaking it.
  void _emitControl(DeviceLinkControlMessage control) {
    final waiter = _controlWaiter;
    if (waiter != null) {
      _controlWaiter = null;
      waiter.complete(control);
      return;
    }
    _pendingControls.addLast(control);
    _drainControls();
  }

  void _emitBinary(DeviceLinkBinaryFrame frame) {
    final waiter = _binaryWaiter;
    if (waiter != null) {
      _binaryWaiter = null;
      waiter.complete(frame);
      return;
    }
    _pendingBinaryFrames.addLast(frame);
    _drainBinaryFrames();
  }

  void _drainControls() {
    if (_closed || !_controls.hasListener) return;
    while (_pendingControls.isNotEmpty) {
      _controls.add(_pendingControls.removeFirst());
    }
  }

  void _drainBinaryFrames() {
    if (_closed || !_binaryFrames.hasListener) return;
    while (_pendingBinaryFrames.isNotEmpty) {
      _binaryFrames.add(_pendingBinaryFrames.removeFirst());
    }
  }

  @override
  bool get isClosed => _closed;

  @override
  bool get isReadOnly => _readOnly;

  Future<void> sendControl(DeviceLinkControlMessage message) async {
    if (_closed) throw _closedError;
    // WebSocket owns this sink and closes it in [close].
    // ignore: close_sinks
    _socket.add(message.encode());
  }

  /// Sends a raw text frame for protocol compatibility tests.
  ///
  /// Production callers should use [sendControl] so outbound messages are
  /// typed and versioned by the protocol model.
  Future<void> sendRawText(String text) async {
    if (_closed) throw _closedError;
    // WebSocket owns this sink and closes it in [close].
    // ignore: close_sinks
    _socket.add(text);
  }

  /// Sends a raw binary frame that bypasses the protocol model's encoder.
  ///
  /// Exists so tests can put a deliberately malformed or oversized frame on
  /// the wire. Production callers must use [sendBinary], which size-checks
  /// every outbound frame.
  @visibleForTesting
  Future<void> sendRawBinary(List<int> bytes) async {
    if (_closed) throw _closedError;
    // WebSocket owns this sink and closes it in [close].
    // ignore: close_sinks
    _socket.add(bytes);
  }

  @override
  Future<void> sendBinary(DeviceLinkBinaryFrame frame) async {
    if (_closed) throw _closedError;
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
    if (_closed) {
      return Future<DeviceLinkControlMessage>.error(_closedError);
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
    if (_closed) {
      return Future<DeviceLinkBinaryFrame>.error(_closedError);
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
    if (message is String) {
      try {
        final control = DeviceLinkControlMessage.decode(message);
        if (control is DeviceLinkAttached) _readOnly = false;
        if (control is DeviceLinkReclaimed) _readOnly = true;
        _emitControl(control);
      } on Object catch (error, stack) {
        _handleProtocolError(error, stack, binary: false);
      }
      return;
    }
    if (message is List<int>) {
      try {
        final frame = DeviceLinkBinaryFrame.decode(message);
        _emitBinary(frame);
      } on Object catch (error, stack) {
        _handleProtocolError(error, stack, binary: true);
      }
      return;
    }
    _handleProtocolError(
      const DeviceLinkProtocolException(
        'invalid_frame',
        'Unsupported WebSocket frame type',
      ),
      StackTrace.current,
      binary: false,
    );
  }

  void _handleProtocolError(
    Object error,
    StackTrace stack, {
    required bool binary,
  }) {
    final controlWaiter = _controlWaiter;
    final binaryWaiter = _binaryWaiter;
    _controlWaiter = null;
    _binaryWaiter = null;

    final matchingWaiter = binary ? binaryWaiter : controlWaiter;
    if (matchingWaiter != null) {
      matchingWaiter.completeError(error, stack);
    } else if (binary) {
      _binaryFrames.addError(error, stack);
    } else {
      _controls.addError(error, stack);
    }

    final otherWaiter = binary ? controlWaiter : binaryWaiter;
    if (otherWaiter != null) {
      otherWaiter.completeError(error, stack);
    }
    if (error is DeviceLinkProtocolException) unawaited(close());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _controlWaiter?.completeError(_closedError);
    _controlWaiter = null;
    _binaryWaiter?.completeError(_closedError);
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
