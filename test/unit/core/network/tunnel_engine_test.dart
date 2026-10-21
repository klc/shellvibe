import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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

    test('a forward stops and is marked failed when its SSH client closes', () async {
      final probe = await ServerSocket.bind('127.0.0.1', 0);
      final port = probe.port;
      await probe.close();
      final client = FakeSSHClient();

      await tunnelEngine.startLocalForward(
        ruleId: 'r_gone',
        hostId: 'h1',
        sshClient: client,
        localPort: port,
        remoteHost: 'example.com',
        remotePort: 80,
      );
      expect(tunnelEngine.isTunnelActive('r_gone'), isTrue);

      client.doneCompleter.complete();
      await pumpEventQueue();

      expect(tunnelEngine.isTunnelActive('r_gone'), isFalse);
      final tunnel = tunnelEngine.activeTunnelsList.singleWhere(
        (t) => t.ruleId == 'r_gone',
      );
      expect(tunnel.error, contains('SSH connection closed'));
      await expectLater(
        Socket.connect('127.0.0.1', port),
        throwsA(isA<SocketException>()),
      );
    });

    test('a forward that carried traffic still stops when its client closes', () async {
      final probe = await ServerSocket.bind('127.0.0.1', 0);
      final port = probe.port;
      await probe.close();
      final client = FakeSSHClient();

      await tunnelEngine.startLocalForward(
        ruleId: 'r_busy',
        hostId: 'h1',
        sshClient: client,
        localPort: port,
        remoteHost: 'example.com',
        remotePort: 80,
      );
      // Bytes through the forward replace the published tunnel object.
      final socket = await Socket.connect('127.0.0.1', port);
      socket.add([1, 2, 3]);
      await socket.flush();
      await pumpEventQueue();
      expect(
        tunnelEngine.activeTunnelsList.single.bytesTransferred,
        greaterThan(0),
      );

      client.doneCompleter.complete();
      await pumpEventQueue();
      socket.destroy();

      expect(tunnelEngine.isTunnelActive('r_busy'), isFalse);
      expect(
        tunnelEngine.activeTunnelsList.single.error,
        contains('SSH connection closed'),
      );
    });

    test('a forward stops when its SSH client ends with an error', () async {
      final probe = await ServerSocket.bind('127.0.0.1', 0);
      final port = probe.port;
      await probe.close();
      final client = FakeSSHClient();

      await tunnelEngine.startLocalForward(
        ruleId: 'r_reset',
        hostId: 'h1',
        sshClient: client,
        localPort: port,
        remoteHost: 'example.com',
        remotePort: 80,
      );

      client.doneCompleter.completeError(StateError('reset'));
      await pumpEventQueue();

      expect(tunnelEngine.isTunnelActive('r_reset'), isFalse);
      final tunnel = tunnelEngine.activeTunnelsList.singleWhere(
        (t) => t.ruleId == 'r_reset',
      );
      expect(tunnel.error, contains('SSH connection closed'));
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

      final tunnel = tunnelEngine.activeTunnelsList.singleWhere(
        (t) => t.ruleId == 'r_fail',
      );
      expect(tunnel.isActive, isFalse);
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

  final Completer<void> doneCompleter = Completer<void>();

  FakeSSHClient({this.remoteForwardResult});

  @override
  Future<void> get done => doneCompleter.future;

  @override
  Future<SSHForwardChannel> forwardLocal(
    String remoteHost,
    int remotePort, {
    String localHost = 'localhost',
    int localPort = 0,
  }) async => _FakeForwardChannel();

  @override
  Future<SSHRemoteForward?> forwardRemote({
    dynamic filter,
    String? host,
    int? port,
  }) async {
    return remoteForwardResult;
  }
}


/// A forward channel whose remote end never answers; what is written to it
/// is buffered.
class _FakeForwardChannel extends Fake implements SSHForwardChannel {
  final _incoming = StreamController<Uint8List>();
  final _outgoing = StreamController<List<int>>();

  @override
  Stream<Uint8List> get stream => _incoming.stream;

  @override
  StreamSink<List<int>> get sink => _outgoing.sink;

  @override
  Future<void> get done => _incoming.done;

  @override
  Future<void> close() async {
    await _outgoing.close();
    await _incoming.close();
  }

  @override
  void destroy() {}
}
