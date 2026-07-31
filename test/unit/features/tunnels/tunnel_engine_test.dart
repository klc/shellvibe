import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/core/network/tunnel_engine.dart';

void main() {
  group('TunnelEngine & ActiveTunnel Unit Tests', () {
    late TunnelEngine tunnelEngine;

    setUp(() {
      tunnelEngine = TunnelEngine();
    });

    tearDown(() {
      tunnelEngine.dispose();
    });

    test('ActiveTunnel formats speed and bytes correctly', () {
      const tunnel = ActiveTunnel(
        ruleId: 'r1',
        hostId: 'h1',
        type: 'local',
        localPort: 8080,
        remoteHost: '127.0.0.1',
        remotePort: 80,
        bytesTransferred: 5242880,
        speedBytesPerSec: 1048576,
      );

      expect(tunnel.formattedType, 'Local (-L)');
      expect(tunnel.formattedSpeed, '1.0 MB/s');
      expect(tunnel.formattedBytes, '5.0 MB');
    });

    test('TunnelEngine starts with empty active tunnels list', () {
      expect(tunnelEngine.activeTunnelsList, isEmpty);
      expect(tunnelEngine.isTunnelActive('r1'), false);
    });

    test('stopTunnel handles non-existing rule gracefully', () async {
      await tunnelEngine.stopTunnel('non-existent');
      expect(tunnelEngine.activeTunnelsList, isEmpty);
    });
  });
}
