import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/tunnel_engine.dart';

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

    test('stopTunnel closes SSHRemoteForward listener and clears active tunnel', () async {
      final fakeListener = FakeSSHRemoteForward();
      final fakeSshClient = FakeSSHClient(remoteForwardResult: fakeListener);

      await tunnelEngine.startRemoteForward(
        ruleId: 'r_remote',
        hostId: 'h1',
        sshClient: fakeSshClient,
        remotePort: 9000,
        localHost: '127.0.0.1',
        localPort: 8000,
      );

      expect(tunnelEngine.isTunnelActive('r_remote'), isTrue);
      expect(fakeListener.isClosed, isFalse);

      await tunnelEngine.stopTunnel('r_remote');

      expect(tunnelEngine.isTunnelActive('r_remote'), isFalse);
      expect(fakeListener.isClosed, isTrue);
    });

    test('stopAllTunnels stops all active remote forward listeners and tunnels', () async {
      final fakeListener1 = FakeSSHRemoteForward();
      final fakeListener2 = FakeSSHRemoteForward();

      final fakeSshClient1 = FakeSSHClient(remoteForwardResult: fakeListener1);
      final fakeSshClient2 = FakeSSHClient(remoteForwardResult: fakeListener2);

      await tunnelEngine.startRemoteForward(
        ruleId: 'r1',
        hostId: 'h1',
        sshClient: fakeSshClient1,
        remotePort: 9001,
        localHost: '127.0.0.1',
        localPort: 8001,
      );

      await tunnelEngine.startRemoteForward(
        ruleId: 'r2',
        hostId: 'h1',
        sshClient: fakeSshClient2,
        remotePort: 9002,
        localHost: '127.0.0.1',
        localPort: 8002,
      );

      expect(tunnelEngine.activeTunnelsList.length, 2);

      await tunnelEngine.stopAllTunnels();

      expect(tunnelEngine.activeTunnelsList, isEmpty);
      expect(fakeListener1.isClosed, isTrue);
      expect(fakeListener2.isClosed, isTrue);
    });

    test('startRemoteForward cleans up resources on error', () async {
      final fakeSshClient = FakeFailingSSHClient();

      await expectLater(
        tunnelEngine.startRemoteForward(
          ruleId: 'r_fail',
          hostId: 'h1',
          sshClient: fakeSshClient,
          remotePort: 9090,
          localHost: '127.0.0.1',
          localPort: 8080,
        ),
        throwsA(isA<Exception>()),
      );

      final tunnel = tunnelEngine.getActiveTunnel('r_fail');
      expect(tunnel, isNotNull);
      expect(tunnel!.isActive, isFalse);
      expect(tunnel.error, contains('Remote forward failed'));
    });
  });
}

class FakeFailingSSHClient extends Fake implements SSHClient {
  @override
  Future<SSHRemoteForward?> forwardRemote({
    dynamic filter,
    String? host,
    int? port,
  }) async {
    throw Exception('Remote forward failed');
  }
}

class FakeSSHRemoteForward extends Fake implements SSHRemoteForward {
  bool isClosed = false;
  final _controller = StreamController<SSHForwardChannel>.broadcast();

  @override
  Stream<SSHForwardChannel> get connections => _controller.stream;

  @override
  void close() {
    isClosed = true;
    _controller.close();
  }
}

class FakeSSHClient extends Fake implements SSHClient {
  final SSHRemoteForward? remoteForwardResult;

  FakeSSHClient({this.remoteForwardResult});

  @override
  Future<SSHRemoteForward?> forwardRemote({
    dynamic filter,
    String? host,
    int? port,
  }) async {
    return remoteForwardResult;
  }
}

