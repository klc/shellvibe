import '../../../../core/network/device_link/device_link_client.dart';
import '../../../../core/network/device_link/device_discovery.dart';
import '../../../../core/network/device_link/device_link_protocol.dart';
import '../../../../core/network/device_link/device_link_server.dart';
import '../../domain/models/device_link_pairing_profile.dart';

final class DeviceLinkAutoReconnectResult {
  final DeviceLinkClientConnection connection;
  final DeviceLinkSessionInfo session;
  final DeviceLinkHelloAck helloAck;

  const DeviceLinkAutoReconnectResult({
    required this.connection,
    required this.session,
    required this.helloAck,
  });
}

/// Reconnects a stored mobile pairing without showing the QR flow again.
final class DeviceLinkAutoReconnectService {
  final DeviceLinkClient client;
  final DeviceDiscovery discovery;

  DeviceLinkAutoReconnectService({
    DeviceLinkClient? client,
    DeviceDiscovery? discovery,
  }) : client = client ?? DeviceLinkClient(),
       discovery = discovery ?? DeviceDiscovery();

  Future<DeviceLinkAutoReconnectResult> connect(
    DeviceLinkPairingProfile profile,
  ) async {
    final hosts = <String>{...profile.addresses, profile.mdns, profile.host}
      ..removeWhere((host) => host.isEmpty);
    final storedEndpoints = hosts
        .map(
          (host) => DeviceLinkEndpoint(
            host: host,
            port: profile.port,
            spkiSha256Base64: profile.spki,
          ),
        )
        .toList();
    final connection = await _connectWithDiscovery(profile, storedEndpoints);
    try {
      await connection.sendHello(
        DeviceLinkHello(
          deviceId: profile.deviceId,
          deviceName: profile.name,
          secret: profile.secret,
        ),
      );
      final response = await connection.nextControl();
      if (response case final DeviceLinkError error) {
        throw DeviceLinkTransportException(error.code, error.message);
      }
      if (response is! DeviceLinkHelloAck) {
        throw const DeviceLinkTransportException(
          'reconnect_rejected',
          'Stored Device Link pairing was rejected',
        );
      }
      final session = _selectSession(response, profile.sessionId);
      return DeviceLinkAutoReconnectResult(
        connection: connection,
        session: session,
        helloAck: response,
      );
    } catch (_) {
      await connection.close();
      rethrow;
    }
  }

  Future<DeviceLinkClientConnection> _connectWithDiscovery(
    DeviceLinkPairingProfile profile,
    List<DeviceLinkEndpoint> storedEndpoints,
  ) async {
    try {
      return await client.connect(storedEndpoints);
    } on Object catch (firstError, firstStack) {
      final discoveredEndpoints = await _discoverEndpoints(profile);
      if (discoveredEndpoints.isEmpty) {
        Error.throwWithStackTrace(firstError, firstStack);
      }
      try {
        return await client.connect([
          ...storedEndpoints,
          ...discoveredEndpoints,
        ]);
      } on Object {
        Error.throwWithStackTrace(firstError, firstStack);
      }
    }
  }

  Future<List<DeviceLinkEndpoint>> _discoverEndpoints(
    DeviceLinkPairingProfile profile,
  ) async {
    if (!discovery.supportsMdns) return const [];
    try {
      final services = await discovery.discover(
        timeout: const Duration(seconds: 1),
      );
      final endpoints = <DeviceLinkEndpoint>[];
      for (final service in services) {
        final port = service.port > 0 ? service.port : profile.port;
        if (port <= 0 || port > 65535) continue;
        for (final address in service.addresses) {
          if (address.isEmpty) continue;
          endpoints.add(
            DeviceLinkEndpoint(
              host: address,
              port: port,
              spkiSha256Base64: profile.spki,
            ),
          );
        }
        final host = service.host;
        if (host != null && host.isNotEmpty) {
          endpoints.add(
            DeviceLinkEndpoint(
              host: host,
              port: port,
              spkiSha256Base64: profile.spki,
            ),
          );
        }
      }
      return endpoints;
    } on Object {
      return const [];
    }
  }

  DeviceLinkSessionInfo _selectSession(
    DeviceLinkHelloAck helloAck,
    String? preferredId,
  ) {
    if (helloAck.sessions.isEmpty) {
      throw const DeviceLinkTransportException(
        'session_gone',
        'No live terminal sessions are available on the desktop',
      );
    }
    for (final session in helloAck.sessions) {
      if (session.id == preferredId) return session;
    }
    return helloAck.sessions.first;
  }
}
