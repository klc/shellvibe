import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';

import 'device_link_identity.dart';
import 'device_link_attachment.dart';
import 'device_link_protocol.dart';
import 'device_link_session_transport.dart';

const deviceLinkMdnsServiceType = '_terly._tcp';
const deviceLinkPingInterval = Duration(seconds: 5);

typedef DeviceLinkSessionListProvider =
    FutureOr<List<DeviceLinkSessionInfo>> Function();

typedef DeviceLinkBinaryFrameHandler =
    FutureOr<void> Function(
      DeviceLinkServerConnection connection,
      DeviceLinkBinaryFrame frame,
    );

typedef DeviceLinkPairedDeviceAuthenticator =
    FutureOr<bool> Function(String deviceId, String secret);

typedef DeviceLinkPairedDevicePersister =
    FutureOr<void> Function(DeviceLinkPairedDeviceRecord device);

typedef DeviceLinkPairingCompletedCallback = FutureOr<void> Function();

/// Values needed to persist a newly paired device. The [secret] is transient:
/// a persister must hash it before it reaches durable storage.
final class DeviceLinkPairedDeviceRecord {
  final String id;
  final String name;
  final String platform;
  final String secret;
  final String publicKey;
  final DateTime pairedAt;

  const DeviceLinkPairedDeviceRecord({
    required this.id,
    required this.name,
    required this.platform,
    required this.secret,
    required this.publicKey,
    required this.pairedAt,
  });
}

/// A QR payload that contains only the information needed for first pairing.
final class DeviceLinkQrPayload {
  final int version;
  final String host;
  final List<String> addresses;
  final String mdns;
  final int port;
  final String spki;
  final String token;
  final DateTime expiresAt;

  DeviceLinkQrPayload({
    required this.version,
    required this.host,
    required List<String> addresses,
    required this.mdns,
    required this.port,
    required this.spki,
    required this.token,
    required this.expiresAt,
  }) : addresses = List.unmodifiable(addresses);

  Map<String, Object?> toJson() => {
    'v': version,
    'host': host,
    'addrs': addresses,
    'mdns': mdns,
    'port': port,
    'spki': spki,
    'token': token,
    'exp': expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000,
  };

  String encode() => jsonEncode(toJson());

  factory DeviceLinkQrPayload.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const DeviceLinkTransportException(
        'invalid_qr_payload',
        'Device Link QR payload must be a JSON object',
      );
    }
    final version = value['v'];
    final host = value['host'];
    final addresses = value['addrs'];
    final mdns = value['mdns'];
    final port = value['port'];
    final spki = value['spki'];
    final token = value['token'];
    final expiry = value['exp'];
    if (version is! int ||
        version != deviceLinkProtocolVersion ||
        host is! String ||
        host.isEmpty ||
        addresses is! List ||
        addresses.any((item) => item is! String) ||
        mdns is! String ||
        mdns.isEmpty ||
        port is! int ||
        port <= 0 ||
        port > 65535 ||
        spki is! String ||
        spki.isEmpty ||
        token is! String ||
        token.isEmpty ||
        expiry is! int) {
      throw const DeviceLinkTransportException(
        'invalid_qr_payload',
        'Device Link QR payload has invalid fields',
      );
    }
    return DeviceLinkQrPayload(
      version: version,
      host: host,
      addresses: List<String>.from(addresses),
      mdns: mdns,
      port: port,
      spki: spki,
      token: token,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiry * 1000,
        isUtc: true,
      ),
    );
  }
}

/// In-memory one-time pairing token store.
final class DeviceLinkPairingTokenStore {
  final Duration ttl;
  final Map<String, DateTime> _tokens = {};
  final Random _random = Random.secure();

  DeviceLinkPairingTokenStore({this.ttl = const Duration(seconds: 90)});

  String issue({DateTime? now}) {
    final current = now ?? DateTime.now().toUtc();
    _purge(current);
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );
    final token = base64Url.encode(bytes).replaceAll('=', '');
    _tokens[token] = current.add(ttl);
    return token;
  }

  bool consume(String token, {DateTime? now}) {
    final current = now ?? DateTime.now().toUtc();
    final expiry = _tokens.remove(token);
    if (expiry == null || !current.isBefore(expiry)) return false;
    return true;
  }

  bool contains(String token, {DateTime? now}) {
    final current = now ?? DateTime.now().toUtc();
    _purge(current);
    return _tokens.containsKey(token);
  }

  void _purge(DateTime now) {
    _tokens.removeWhere((_, expiry) => !now.isBefore(expiry));
  }
}

/// TLS/WebSocket server running on the desktop side of Device Link.
final class DeviceLinkServer {
  final DeviceLinkIdentity identity;
  final String hostName;
  final String appVersion;
  final InternetAddress bindAddress;
  final int requestedPort;
  final Duration pairingTokenTtl;
  final DeviceLinkSessionListProvider sessionsProvider;
  final DeviceLinkSessionTransportListProvider? sessionTransportsProvider;
  final DeviceLinkSessionTransportResolver? sessionTransportResolver;
  final DeviceLinkBinaryFrameHandler? onBinaryFrame;
  final DeviceLinkPairedDeviceAuthenticator? pairedDeviceAuthenticator;
  final DeviceLinkPairedDevicePersister? pairedDevicePersister;
  final DeviceLinkPairingCompletedCallback? onPairingCompleted;

  late final DeviceLinkPairingTokenStore pairingTokens =
      DeviceLinkPairingTokenStore(ttl: pairingTokenTtl);

  HttpServer? _httpServer;
  final Set<DeviceLinkServerConnection> _connections = {};
  final Map<String, _PairedDevice> _pairedDevices = {};

  DeviceLinkServer({
    required this.identity,
    required this.hostName,
    required this.appVersion,
    InternetAddress? bindAddress,
    this.requestedPort = 0,
    this.pairingTokenTtl = const Duration(seconds: 90),
    DeviceLinkSessionListProvider? sessionsProvider,
    this.sessionTransportsProvider,
    this.sessionTransportResolver,
    this.onBinaryFrame,
    this.pairedDeviceAuthenticator,
    this.pairedDevicePersister,
    this.onPairingCompleted,
  }) : bindAddress = bindAddress ?? InternetAddress.anyIPv4,
       sessionsProvider = sessionsProvider ?? _emptySessions;

  bool get isRunning => _httpServer != null;

  int get port {
    final server = _httpServer;
    if (server == null) {
      throw const DeviceLinkTransportException(
        'server_not_started',
        'Device Link server has not started',
      );
    }
    return server.port;
  }

  Future<void> start() async {
    if (isRunning) return;
    try {
      _httpServer = await HttpServer.bindSecure(
        bindAddress,
        requestedPort,
        identity.createServerSecurityContext(),
      );
      _httpServer!.listen(_handleRequest, onError: (_) {});
    } catch (error) {
      _httpServer = null;
      throw DeviceLinkTransportException(
        'server_start_failed',
        'Could not start the Device Link TLS server',
        error,
      );
    }
  }

  Future<DeviceLinkQrPayload> createPairingPayload({
    String? mdnsName,
    List<String>? addresses,
    DateTime? now,
  }) async {
    if (!isRunning) {
      throw const DeviceLinkTransportException(
        'server_not_started',
        'Device Link server must be started before creating a QR payload',
      );
    }
    final current = (now ?? DateTime.now()).toUtc();
    final candidates = addresses ?? await _nonLoopbackAddresses();
    return DeviceLinkQrPayload(
      version: deviceLinkProtocolVersion,
      host: hostName,
      addresses: candidates,
      mdns: mdnsName ?? '$hostName.$deviceLinkMdnsServiceType.local',
      port: port,
      spki: identity.spkiSha256Base64,
      token: pairingTokens.issue(now: current),
      expiresAt: current.add(pairingTokenTtl),
    );
  }

  Future<void> close() async {
    final connections = List<DeviceLinkServerConnection>.from(_connections);
    for (final connection in connections) {
      await connection.close();
    }
    _connections.clear();
    await _httpServer?.close(force: true);
    _httpServer = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path != '/device-link' ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType.text
        ..write('Not found');
      await request.response.close();
      return;
    }

    try {
      // The WebSocket owns the upgraded HTTP sink after upgrade.
      // ignore: close_sinks
      final socket = await WebSocketTransformer.upgrade(request);
      socket.pingInterval = deviceLinkPingInterval;
      final connection = DeviceLinkServerConnection._(this, socket);
      _connections.add(connection);
      connection._listen();
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<List<DeviceLinkSessionInfo>> _sessions() async {
    final transports = sessionTransportsProvider;
    if (transports != null) {
      final sessions = await transports();
      return List.unmodifiable(sessions.map((transport) => transport.info));
    }
    final sessions = await sessionsProvider();
    return List.unmodifiable(sessions);
  }

  Future<DeviceLinkSessionTransport?> _resolveTransport(
    String sessionId,
  ) async {
    final resolver = sessionTransportResolver;
    if (resolver != null) return resolver(sessionId);
    final listProvider = sessionTransportsProvider;
    if (listProvider == null) return null;
    final transports = await listProvider();
    for (final transport in transports) {
      if (transport.info.id == sessionId) return transport;
    }
    return null;
  }

  Future<bool> _authenticate(String deviceId, String secret) async {
    final authenticator = pairedDeviceAuthenticator;
    if (authenticator != null) return authenticator(deviceId, secret);
    final paired = _pairedDevices[deviceId];
    if (paired == null) return false;
    final actual = CryptoUtils.getHashPlain(
      Uint8List.fromList(utf8.encode(secret)),
      algorithmName: 'SHA-256',
    );
    return _constantTimeBytesEqual(actual, paired.secretHash);
  }

  String _createSecret() {
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<void> _handleControl(
    DeviceLinkServerConnection connection,
    DeviceLinkControlMessage message,
  ) async {
    if (message is DeviceLinkHello) {
      if (connection.helloReceived) {
        await connection._error('unexpected_message', 'Hello already received');
        return;
      }
      connection._deviceId = message.deviceId;
      connection._deviceName = message.deviceName;
      connection._helloReceived = true;
      if (message.secret != null) {
        if (!await _authenticate(message.deviceId, message.secret!)) {
          await connection._error(
            'unauthorized',
            'Device Link secret rejected',
          );
          await connection.close();
          return;
        }
        connection._authenticated = true;
      }
      await connection.sendControl(
        DeviceLinkHelloAck(appVersion: appVersion, sessions: await _sessions()),
      );
      return;
    }

    if (!connection.helloReceived) {
      await connection._error('handshake_required', 'Hello is required first');
      return;
    }

    if (message is DeviceLinkPair) {
      if (!pairingTokens.consume(message.token)) {
        await connection._error(
          'pairing_token_invalid',
          'Pairing token is invalid or expired',
        );
        return;
      }
      final secret = _createSecret();
      final deviceId = connection.deviceId ?? message.deviceName;
      final pairedAt = DateTime.now().toUtc();
      final persister = pairedDevicePersister;
      if (persister != null) {
        try {
          await persister(
            DeviceLinkPairedDeviceRecord(
              id: deviceId,
              name: message.deviceName,
              platform: message.platform ?? 'unknown',
              secret: secret,
              publicKey: message.devicePublicKey,
              pairedAt: pairedAt,
            ),
          );
        } catch (_) {
          await connection._error(
            'pairing_failed',
            'The paired device could not be stored',
          );
          return;
        }
      } else {
        final hash = CryptoUtils.getHashPlain(
          Uint8List.fromList(utf8.encode(secret)),
          algorithmName: 'SHA-256',
        );
        _pairedDevices[deviceId] = _PairedDevice(
          secretHash: hash,
          publicKey: message.devicePublicKey,
        );
      }
      connection._authenticated = true;
      await connection.sendControl(
        DeviceLinkPaired(secret: secret, hostName: hostName),
      );
      final pairingCompleted = onPairingCompleted;
      if (pairingCompleted != null) await pairingCompleted();
      return;
    }

    if (message is DeviceLinkAttach ||
        message is DeviceLinkResize ||
        message is DeviceLinkDetach) {
      if (!connection.isAuthenticated) {
        await connection._error(
          'unauthorized',
          'Device Link authentication is required',
        );
        return;
      }
      if (message case final DeviceLinkAttach attach) {
        await _attach(connection, attach);
      } else if (message case final DeviceLinkResize resize) {
        await _resize(connection, resize);
      } else {
        await _detach(connection);
      }
      return;
    }

    if (message is DeviceLinkError) return;
    await connection._error(
      'unexpected_message',
      'Control message is not valid here',
    );
  }

  Future<void> _attach(
    DeviceLinkServerConnection connection,
    DeviceLinkAttach request,
  ) async {
    if (connection._attachedTransport != null) {
      await connection._error(
        'already_attached',
        'This Device Link connection already owns a terminal session',
      );
      return;
    }
    final transport = await _resolveTransport(request.sessionId);
    if (transport == null) {
      await connection._error(
        'session_gone',
        'The requested terminal session is no longer available',
      );
      return;
    }

    // Publish ownership before the resize/snapshot await points. A desktop
    // key can reclaim the session while attach is completing.
    connection._attachedTransport = transport;
    try {
      final result = await transport.attach(
        connection: connection,
        request: request,
        onDesktopInput: () => _reclaim(connection),
      );
      if (connection.isClosed) {
        await _releaseAttachment(connection, notify: false);
        return;
      }
      await connection.sendControl(result.attached);
      await connection.sendBinary(
        DeviceLinkBinaryFrame(
          type: DeviceLinkBinaryFrameType.snapshot,
          payload: result.snapshotPayload,
        ),
      );
    } on DeviceLinkSessionException catch (error) {
      connection._attachedTransport = null;
      await connection._error(error.code, error.message);
    } catch (_) {
      connection._attachedTransport = null;
      await connection._error(
        'attach_failed',
        'The terminal session could not be attached',
      );
    }
  }

  Future<void> _resize(
    DeviceLinkServerConnection connection,
    DeviceLinkResize request,
  ) async {
    final transport = connection._attachedTransport;
    if (transport == null) {
      await connection._error(
        'session_not_attached',
        'Attach a terminal session before resizing it',
      );
      return;
    }
    try {
      await transport.resize(
        connection: connection,
        columns: request.cols,
        rows: request.rows,
      );
    } on DeviceLinkSessionException catch (error) {
      await connection._error(error.code, error.message);
    } catch (_) {
      await connection._error(
        'resize_failed',
        'The terminal session could not be resized',
      );
    }
  }

  Future<void> _detach(DeviceLinkServerConnection connection) async {
    final transport = connection._attachedTransport;
    if (transport == null) {
      await connection._error(
        'session_not_attached',
        'This Device Link connection does not own a terminal session',
      );
      return;
    }
    await _releaseAttachment(connection, notify: false);
  }

  Future<void> _reclaim(DeviceLinkServerConnection connection) async {
    final attachment = await _releaseAttachment(connection, notify: false);
    if (attachment == null || connection.isClosed) return;
    await connection.sendControl(
      DeviceLinkReclaimed(
        cols: attachment.previousColumns,
        rows: attachment.previousRows,
      ),
    );
  }

  Future<DeviceLinkAttachment?> _releaseAttachment(
    DeviceLinkServerConnection connection, {
    required bool notify,
  }) async {
    final transport = connection._attachedTransport;
    if (transport == null) return null;
    connection._attachedTransport = null;
    try {
      final attachment = await transport.detach(connection: connection);
      if (notify && attachment != null && !connection.isClosed) {
        await connection.sendControl(
          DeviceLinkReclaimed(
            cols: attachment.previousColumns,
            rows: attachment.previousRows,
          ),
        );
      }
      return attachment;
    } on DeviceLinkSessionException {
      return null;
    }
  }

  Future<void> _connectionClosed(DeviceLinkServerConnection connection) async {
    await _releaseAttachment(connection, notify: false);
  }

  Future<void> _handleBinary(
    DeviceLinkServerConnection connection,
    DeviceLinkBinaryFrame frame,
  ) async {
    final transport = connection._attachedTransport;
    if (frame.type == DeviceLinkBinaryFrameType.ptyInput && transport != null) {
      try {
        await transport.writeInput(
          connection: connection,
          bytes: frame.payload,
        );
      } on DeviceLinkSessionException catch (error) {
        await connection._error(error.code, error.message);
      } catch (_) {
        await connection._error(
          'input_failed',
          'Device Link input could not be delivered',
        );
      }
      return;
    }
    if (frame.type != DeviceLinkBinaryFrameType.ptyInput) {
      await connection._error(
        'invalid_binary_direction',
        'This binary frame is not valid from the Device Link client',
      );
      return;
    }
    // Retain the Phase 1 diagnostic hook when no real session registry is
    // configured. Once a registry is supplied, every client input must belong
    // to an attached session and never fall through to a generic callback.
    if (sessionTransportResolver == null &&
        sessionTransportsProvider == null &&
        onBinaryFrame != null) {
      await onBinaryFrame!.call(connection, frame);
      return;
    }
    await connection._error(
      'session_not_attached',
      'Attach a terminal session before sending input',
    );
  }

  void _remove(DeviceLinkServerConnection connection) {
    _connections.remove(connection);
  }

  static Future<List<DeviceLinkSessionInfo>> _emptySessions() async =>
      <DeviceLinkSessionInfo>[];

  static Future<List<String>> _nonLoopbackAddresses() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.any,
    );
    final addresses = <String>{};
    for (final networkInterface in interfaces) {
      for (final address in networkInterface.addresses) {
        if (!address.isLoopback) addresses.add(address.address);
      }
    }
    return addresses.toList()..sort();
  }
}

/// A server-side WebSocket connection.
final class DeviceLinkServerConnection {
  final DeviceLinkServer _server;
  final WebSocket _socket;
  StreamSubscription<Object?>? _subscription;
  Future<void> _messageQueue = Future<void>.value();
  bool _closed = false;
  bool _helloReceived = false;
  bool _authenticated = false;
  String? _deviceId;
  String? _deviceName;
  DeviceLinkSessionTransport? _attachedTransport;

  DeviceLinkServerConnection._(this._server, this._socket);

  String? get deviceId => _deviceId;
  String? get deviceName => _deviceName;
  bool get helloReceived => _helloReceived;
  bool get isAuthenticated => _authenticated;
  bool get isClosed => _closed;

  void _listen() {
    _subscription = _socket.listen(
      (Object? message) {
        _messageQueue = _messageQueue.then((_) => _handle(message));
      },
      onError: (_, _) => close(),
      onDone: close,
      cancelOnError: true,
    );
  }

  Future<void> sendControl(DeviceLinkControlMessage message) async {
    if (_closed) return;
    // WebSocket owns this sink and closes it in [close].
    // ignore: close_sinks
    _socket.add(message.encode());
  }

  Future<void> sendBinary(DeviceLinkBinaryFrame frame) async {
    if (_closed) return;
    // WebSocket owns this sink and closes it in [close].
    // ignore: close_sinks
    _socket.add(frame.encode());
  }

  Future<void> _handle(Object? message) async {
    if (_closed) return;
    if (message is String) {
      try {
        await _server._handleControl(
          this,
          DeviceLinkControlMessage.decode(message),
        );
      } on DeviceLinkUnsupportedVersionException {
        await _error(
          'unsupported_version',
          'Unsupported Device Link protocol version',
        );
        await close();
      } on DeviceLinkProtocolException catch (error) {
        await _error(error.code, error.message);
      } catch (_) {
        await _error(
          'invalid_control_frame',
          'Invalid Device Link control frame',
        );
      }
      return;
    }
    if (message is List<int>) {
      if (!_helloReceived) {
        await _error('handshake_required', 'Hello is required first');
        return;
      }
      if (!_authenticated) {
        await _error('unauthorized', 'Device Link authentication is required');
        return;
      }
      try {
        final frame = DeviceLinkBinaryFrame.decode(message);
        await _server._handleBinary(this, frame);
      } on DeviceLinkProtocolException catch (error) {
        await _error(error.code, error.message);
      } catch (_) {
        await _error(
          'binary_frame_failed',
          'Device Link binary frame could not be processed',
        );
      }
      return;
    }
    await _error('invalid_frame', 'Unsupported WebSocket frame type');
  }

  Future<void> _error(String code, String message) =>
      sendControl(DeviceLinkError(code: code, message: message));

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server._connectionClosed(this);
    await _subscription?.cancel();
    _subscription = null;
    _server._remove(this);
    try {
      await _socket.close(WebSocketStatus.normalClosure);
    } catch (_) {}
  }
}

final class _PairedDevice {
  final Uint8List secretHash;
  final String publicKey;

  _PairedDevice({required List<int> secretHash, required this.publicKey})
    : secretHash = Uint8List.fromList(secretHash);
}

bool _constantTimeBytesEqual(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final length = left.length < right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}

/// Transport-level error that deliberately excludes sensitive values.
class DeviceLinkTransportException implements Exception {
  final String code;
  final String message;
  final Object? cause;

  const DeviceLinkTransportException(this.code, this.message, [this.cause]);

  @override
  String toString() => 'DeviceLinkTransportException($code): $message';
}
