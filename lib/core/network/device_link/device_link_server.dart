import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../crypto/encryption_engine.dart';
import 'device_link_identity.dart';
import 'device_link_attachment.dart';
import 'device_link_protocol.dart';
import 'device_link_session_transport.dart';

const deviceLinkMdnsServiceType = '_shellvibe._tcp';
const deviceLinkPingInterval = Duration(seconds: 5);

typedef DeviceLinkSessionListProvider =
    FutureOr<List<DeviceLinkSessionInfo>> Function();

typedef DeviceLinkPairedDeviceAuthenticator =
    FutureOr<bool> Function(String deviceId, String secret);

typedef DeviceLinkPairedDevicePersister =
    FutureOr<void> Function(DeviceLinkPairedDeviceRecord device);

typedef DeviceLinkPairedDeviceRemover =
    FutureOr<void> Function(String deviceId);

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

  DeviceLinkPairingTokenStore({this.ttl = const Duration(seconds: 90)});

  String issue({DateTime? now}) {
    final current = now ?? DateTime.now().toUtc();
    _purge(current);
    final token = base64UrlNoPad(secureRandomBytes(32));
    _tokens[token] = current.add(ttl);
    return token;
  }

  bool consume(String token, {DateTime? now}) {
    final current = now ?? DateTime.now().toUtc();
    final expiry = _tokens.remove(token);
    if (expiry == null || !current.isBefore(expiry)) return false;
    return true;
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

  /// The sessions a phone can attach to. Production always supplies this;
  /// [sessionsProvider] only lists sessions, for a server that never attaches.
  final DeviceLinkSessionTransportListProvider? sessionTransportsProvider;
  final DeviceLinkSessionListProvider? sessionsProvider;
  final DeviceLinkPairedDeviceAuthenticator pairedDeviceAuthenticator;
  final DeviceLinkPairedDevicePersister pairedDevicePersister;
  final DeviceLinkPairedDeviceRemover? pairedDeviceRemover;
  final DeviceLinkPairingCompletedCallback? onPairingCompleted;

  late final DeviceLinkPairingTokenStore pairingTokens =
      DeviceLinkPairingTokenStore(ttl: pairingTokenTtl);

  HttpServer? _httpServer;
  final Set<DeviceLinkServerConnection> _connections = {};

  DeviceLinkServer({
    required this.identity,
    required this.hostName,
    required this.appVersion,
    InternetAddress? bindAddress,
    this.requestedPort = 0,
    this.pairingTokenTtl = const Duration(seconds: 90),
    this.sessionTransportsProvider,
    this.sessionsProvider,
    required this.pairedDeviceAuthenticator,
    required this.pairedDevicePersister,
    this.pairedDeviceRemover,
    this.onPairingCompleted,
  }) : bindAddress = bindAddress ?? InternetAddress.anyIPv4;

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
    final candidates = addresses ?? await _nonLoopbackAddresses(bindAddress);
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

  /// Closes every live connection of [deviceId], e.g. once its pairing is gone.
  Future<void> disconnectDevice(String deviceId) async {
    final matching = _connections.where((c) => c.deviceId == deviceId).toList();
    for (final connection in matching) {
      await connection.close();
    }
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
      // Frame-size limits (see device_link_protocol.dart) are enforced on
      // decode, which is *after* dart:io has buffered the whole message:
      // WebSocketTransformer exposes no maximum message size. The pin is on
      // the server certificate, so it authenticates this desktop to the phone
      // and not the other way round — any LAN peer that completes the
      // handshake reaches the framing layer before the pairing secret is
      // checked, and can make this process allocate an oversized payload.
      // What the limits do buy: an oversized frame closes the connection
      // instead of only erroring, so a single socket cannot repeat it, and no
      // oversized payload ever reaches the PTY or the snapshot decoder.
      // Capping the allocation itself would mean framing the socket by hand.
      //
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
    return List.unmodifiable(await sessionsProvider?.call() ?? const []);
  }

  Future<DeviceLinkSessionTransport?> _resolveTransport(
    String sessionId,
  ) async {
    final listProvider = sessionTransportsProvider;
    if (listProvider == null) return null;
    for (final transport in await listProvider()) {
      if (transport.info.id == sessionId) return transport;
    }
    return null;
  }

  /// Removes the authorization rows a freshly paired phone says were its own.
  ///
  /// Each claim carries the secret this desktop issued for that id, so a claim
  /// is honoured only when it authenticates: holding a pairing token is not
  /// enough to delete a row belonging to somebody else's phone. Nothing here
  /// may fail the pairing — the new authorization is already stored, and a
  /// stale row left behind is only cosmetic.
  Future<void> _dropSupersededDevices(
    String pairedDeviceId,
    List<DeviceLinkSupersededDevice> claims,
  ) async {
    final remover = pairedDeviceRemover;
    if (remover == null) return;
    final seen = <String>{pairedDeviceId};
    for (final claim in claims) {
      if (!seen.add(claim.deviceId)) continue;
      try {
        if (!await pairedDeviceAuthenticator(claim.deviceId, claim.secret)) {
          continue;
        }
        await remover(claim.deviceId);
        await disconnectDevice(claim.deviceId);
      } on Object {
        // A failed removal must not cost the phone its new pairing.
      }
    }
  }

  Future<void> _handleControl(
    DeviceLinkServerConnection connection,
    DeviceLinkControlMessage message,
  ) async {
    switch (message) {
      case final DeviceLinkHello hello:
        await _onHello(connection, hello);
      case _ when !connection.helloReceived:
        await connection._error(
          'handshake_required',
          'Hello is required first',
        );
      case final DeviceLinkPair pair:
        await _onPair(connection, pair);
      case DeviceLinkAttach() || DeviceLinkResize() || DeviceLinkDetach()
          when !connection.isAuthenticated:
        await connection._error(
          'unauthorized',
          'Device Link authentication is required',
        );
      case final DeviceLinkAttach attach:
        await _attach(connection, attach);
      case final DeviceLinkResize resize:
        await _resize(connection, resize);
      case DeviceLinkDetach():
        await _detach(connection);
      case DeviceLinkError():
        break;
      default:
        await connection._error(
          'unexpected_message',
          'Control message is not valid here',
        );
    }
  }

  Future<void> _onHello(
    DeviceLinkServerConnection connection,
    DeviceLinkHello hello,
  ) async {
    if (connection.helloReceived) {
      await connection._error('unexpected_message', 'Hello already received');
      return;
    }
    connection._recordHello(hello.deviceId, hello.deviceName);
    final secret = hello.secret;
    if (secret != null) {
      if (!await pairedDeviceAuthenticator(hello.deviceId, secret)) {
        await connection._error('unauthorized', 'Device Link secret rejected');
        await connection.close();
        return;
      }
      connection._markAuthenticated();
    }
    // An unauthenticated hello exposes no session metadata.
    final sessions = connection.isAuthenticated
        ? await _sessions()
        : const <DeviceLinkSessionInfo>[];
    await connection.sendControl(
      DeviceLinkHelloAck(appVersion: appVersion, sessions: sessions),
    );
  }

  Future<void> _onPair(
    DeviceLinkServerConnection connection,
    DeviceLinkPair pair,
  ) async {
    if (!pairingTokens.consume(pair.token)) {
      await connection._error(
        'pairing_token_invalid',
        'Pairing token is invalid or expired',
      );
      return;
    }
    final secret = base64UrlNoPad(secureRandomBytes(32));
    final deviceId = connection.deviceId!;
    try {
      await pairedDevicePersister(
        DeviceLinkPairedDeviceRecord(
          id: deviceId,
          name: pair.deviceName,
          platform: pair.platform ?? 'unknown',
          secret: secret,
          publicKey: pair.devicePublicKey,
          pairedAt: DateTime.now().toUtc(),
        ),
      );
    } catch (_) {
      await connection._error(
        'pairing_failed',
        'The paired device could not be stored',
      );
      return;
    }
    await _dropSupersededDevices(deviceId, pair.supersedes);
    connection._markAuthenticated();
    await connection.sendControl(
      DeviceLinkPaired(secret: secret, hostName: hostName),
    );
    // The session list follows only now that the one-time pairing secret has
    // authenticated this connection, so the phone can choose its first session.
    await connection.sendControl(
      DeviceLinkHelloAck(appVersion: appVersion, sessions: await _sessions()),
    );
    await onPairingCompleted?.call();
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

    await _retireStaleOwner(transport, connection);

    // Publish ownership before the resize/snapshot await points, so a detach
    // arriving while attach is still completing finds something to release.
    connection._attachedTransport = transport;
    try {
      final result = await transport.attach(
        connection: connection,
        request: request,
      );
      if (!identical(connection._attachedTransport, transport)) {
        // The connection closed or detached while attach was still running.
        // That release can reach the transport before it has recorded this
        // owner, in which case it had nothing to undo; left alone, the
        // transport stays attached to a connection that is gone and every
        // later phone gets `session_in_use` until the tab is closed.
        try {
          await transport.detach(connection: connection);
        } on DeviceLinkSessionException {
          // The earlier release did reach it after all.
        }
        return;
      }
      if (connection.isClosed) {
        await _releaseAttachment(connection);
        return;
      }
      if (result.snapshotPayload.length > deviceLinkMaxSnapshotPayloadLength) {
        await _releaseAttachment(connection);
        await connection._error(
          'snapshot_too_large',
          'The terminal snapshot exceeds the maximum Device Link payload size',
        );
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
      await _releaseAttachment(connection);
      await connection._error(error.code, error.message);
    } catch (_) {
      await _releaseAttachment(connection);
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
    await _releaseAttachment(connection);
  }

  /// Ends the sharing and gives the desktop terminal its dimensions back.
  Future<DeviceLinkAttachment?> _releaseAttachment(
    DeviceLinkServerConnection connection,
  ) async {
    final transport = connection._attachedTransport;
    if (transport == null) return null;
    connection._attachedTransport = null;
    try {
      return await transport.detach(connection: connection);
    } on DeviceLinkSessionException {
      return null;
    }
  }

  Future<void> _connectionClosed(DeviceLinkServerConnection connection) async {
    await _releaseAttachment(connection);
  }

  Future<void> _handleBinary(
    DeviceLinkServerConnection connection,
    DeviceLinkBinaryFrame frame,
  ) async {
    if (frame.type != DeviceLinkBinaryFrameType.ptyInput) {
      await connection._error(
        'invalid_binary_direction',
        'This binary frame is not valid from the Device Link client',
      );
      return;
    }
    final transport = connection._attachedTransport;
    if (transport == null) {
      await connection._error(
        'session_not_attached',
        'Attach a terminal session before sending input',
      );
      return;
    }
    try {
      await transport.writeInput(connection: connection, bytes: frame.payload);
    } on DeviceLinkSessionException catch (error) {
      await connection._error(error.code, error.message);
    } catch (_) {
      await connection._error(
        'input_failed',
        'Device Link input could not be delivered',
      );
    }
  }

  /// Frees a session whose owner is gone but has not been noticed yet.
  ///
  /// A phone comes back on a new socket — a rescan, an app restart, a network
  /// flip — while the old one can still look alive: a half-open TCP connection
  /// is only detected at the ping timeout, and until then its session cannot be
  /// attached to, so the returning phone is met with `session_in_use` for no
  /// reason it can see.
  ///
  /// Only an owner that is already closed, or that is *the same device*
  /// arriving again, is retired. A different phone that is genuinely still
  /// there keeps the session, and the newcomer gets `session_in_use` as before
  /// — a live session is never taken out from under someone.
  Future<void> _retireStaleOwner(
    DeviceLinkSessionTransport transport,
    DeviceLinkServerConnection claimant,
  ) async {
    if (!transport.isAttached) return;
    for (final owner in List<DeviceLinkServerConnection>.from(_connections)) {
      if (identical(owner, claimant)) continue;
      if (!identical(owner._attachedTransport, transport)) continue;
      final sameDevice =
          claimant.deviceId != null && owner.deviceId == claimant.deviceId;
      if (!owner.isClosed && !sameDevice) continue;
      await _releaseAttachment(owner);
      // The stale socket must not keep writing to a session it no longer owns.
      if (!owner.isClosed) await owner.close();
    }
  }

  void _remove(DeviceLinkServerConnection connection) {
    _connections.remove(connection);
  }

  /// Local addresses the phone can dial for a listener bound to [bindAddress].
  ///
  /// An IPv4 bind cannot answer on an IPv6 address, so advertising one would
  /// waste a QR candidate. An IPv6 wildcard bind is dual-stack on every
  /// platform this ships to, so it keeps IPv4 candidates as well — those are
  /// the ones most home networks actually route.
  static Future<List<String>> _nonLoopbackAddresses(
    InternetAddress bindAddress,
  ) async {
    final addressType = bindAddress.type == InternetAddressType.IPv4
        ? InternetAddressType.IPv4
        : InternetAddressType.any;
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: addressType,
    );
    final addresses = <String>{};
    for (final networkInterface in interfaces) {
      for (final address in networkInterface.addresses) {
        if (address.isLoopback) continue;
        if (addressType != InternetAddressType.any &&
            address.type != addressType) {
          continue;
        }
        addresses.add(address.address);
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

  void _recordHello(String deviceId, String deviceName) {
    _deviceId = deviceId;
    _deviceName = deviceName;
    _helloReceived = true;
  }

  /// The peer proved it holds a paired-device secret, or was just issued one.
  void _markAuthenticated() => _authenticated = true;

  void _listen() {
    _subscription = _socket.listen(
      (Object? message) {
        // A link that completes with an error turns the whole chain into an
        // error future, and every frame after it is skipped — the connection
        // goes deaf without closing. `_handle` reports failures to the peer
        // itself, and that report can throw in turn when the socket is already
        // gone, so the queue swallows what is left rather than poisoning
        // itself.
        _messageQueue = _messageQueue
            .then((_) => _handle(message))
            .catchError((Object _) {});
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
        await _protocolErrorAndClose(
          'unsupported_version',
          'Unsupported Device Link protocol version',
        );
      } on DeviceLinkProtocolException catch (error) {
        await _protocolErrorAndClose(error.code, error.message);
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
        await _protocolErrorAndClose(error.code, error.message);
      } catch (_) {
        await _error(
          'binary_frame_failed',
          'Device Link binary frame could not be processed',
        );
      }
      return;
    }
    await _protocolErrorAndClose(
      'invalid_frame',
      'Unsupported WebSocket frame type',
    );
  }

  Future<void> _error(String code, String message) =>
      sendControl(DeviceLinkError(code: code, message: message));

  Future<void> _protocolErrorAndClose(String code, String message) async {
    await _error(code, message);
    await close();
  }

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

/// Transport-level error that deliberately excludes sensitive values.
class DeviceLinkTransportException implements Exception {
  final String code;
  final String message;
  final Object? cause;

  const DeviceLinkTransportException(this.code, this.message, [this.cause]);

  @override
  String toString() => 'DeviceLinkTransportException($code): $message';
}
