import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'socks5_proxy_server.dart';

class ActiveTunnel {
  final String ruleId;
  final String hostId;
  final String type; // 'local', 'remote', 'dynamic'
  final int localPort;
  final String? remoteHost;
  final int? remotePort;
  final bool isActive;
  final int bytesTransferred;
  final int speedBytesPerSec;
  final String? error;

  const ActiveTunnel({
    required this.ruleId,
    required this.hostId,
    required this.type,
    required this.localPort,
    this.remoteHost,
    this.remotePort,
    this.isActive = true,
    this.bytesTransferred = 0,
    this.speedBytesPerSec = 0,
    this.error,
  });

  String get formattedType {
    switch (type) {
      case 'local':
        return 'Local (-L)';
      case 'remote':
        return 'Remote (-R)';
      case 'dynamic':
        return 'Dynamic SOCKS5 (-D)';
      default:
        return type.toUpperCase();
    }
  }

  String get formattedSpeed {
    if (speedBytesPerSec <= 0) return '0 B/s';
    if (speedBytesPerSec < 1024) return '$speedBytesPerSec B/s';
    if (speedBytesPerSec < 1024 * 1024) return '${(speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String get formattedBytes {
    if (bytesTransferred < 1024) return '$bytesTransferred B';
    if (bytesTransferred < 1024 * 1024) return '${(bytesTransferred / 1024).toStringAsFixed(1)} KB';
    if (bytesTransferred < 1024 * 1024 * 1024) return '${(bytesTransferred / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytesTransferred / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  ActiveTunnel copyWith({
    String? ruleId,
    String? hostId,
    String? type,
    int? localPort,
    String? remoteHost,
    int? remotePort,
    bool? isActive,
    int? bytesTransferred,
    int? speedBytesPerSec,
    String? error,
  }) {
    return ActiveTunnel(
      ruleId: ruleId ?? this.ruleId,
      hostId: hostId ?? this.hostId,
      type: type ?? this.type,
      localPort: localPort ?? this.localPort,
      remoteHost: remoteHost ?? this.remoteHost,
      remotePort: remotePort ?? this.remotePort,
      isActive: isActive ?? this.isActive,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      error: error ?? this.error,
    );
  }
}

/// Tunnel Engine managing Local (-L), Remote (-R), and Dynamic SOCKS5 (-D) port forwarding servers.
class TunnelEngine {
  final Map<String, ActiveTunnel> _activeTunnels = {};
  final Map<String, ServerSocket> _localServers = {};
  final Map<String, Socks5ProxyServer> _socksServers = {};
  final Map<String, SSHRemoteForward?> _remoteListeners = {};
  final Map<String, List<StreamSubscription>> _subscriptions = {};

  final StreamController<List<ActiveTunnel>> _tunnelsController =
      StreamController<List<ActiveTunnel>>.broadcast();

  Timer? _statsTimer;
  final Map<String, int> _lastBytesSample = {};
  final Map<String, int> _lastSampleTime = {};

  TunnelEngine() {
    _startStatsTimer();
  }

  Stream<List<ActiveTunnel>> watchActiveTunnels() async* {
    yield activeTunnelsList;
    yield* _tunnelsController.stream;
  }

  List<ActiveTunnel> get activeTunnelsList => _activeTunnels.values.toList();

  ActiveTunnel? getActiveTunnel(String ruleId) => _activeTunnels[ruleId];

  bool isTunnelActive(String ruleId) => _activeTunnels[ruleId]?.isActive ?? false;

  /// Start Local Port Forwarding (-L)
  Future<void> startLocalForward({
    required String ruleId,
    required String hostId,
    required SSHClient sshClient,
    required int localPort,
    required String remoteHost,
    required int remotePort,
  }) async {
    await stopTunnel(ruleId);

    try {
      final serverSocket = await ServerSocket.bind('127.0.0.1', localPort);
      _localServers[ruleId] = serverSocket;
      _subscriptions[ruleId] = [];

      final active = ActiveTunnel(
        ruleId: ruleId,
        hostId: hostId,
        type: 'local',
        localPort: localPort,
        remoteHost: remoteHost,
        remotePort: remotePort,
        isActive: true,
      );

      _activeTunnels[ruleId] = active;
      _notify();

      serverSocket.listen((clientSocket) async {
        try {
          final sshChannel = await sshClient.forwardLocal(remoteHost, remotePort);

          StreamSubscription? sub1;
          StreamSubscription? sub2;
          bool cleanedUp = false;

          void cleanupSubscriptions() {
            if (cleanedUp) return;
            cleanedUp = true;
            sub1?.cancel();
            sub2?.cancel();
            if (sub1 != null) {
              _subscriptions[ruleId]?.remove(sub1);
            }
            if (sub2 != null) {
              _subscriptions[ruleId]?.remove(sub2);
            }
          }

          sub1 = clientSocket.listen(
            (data) {
              sshChannel.sink.add(data);
              _addBytes(ruleId, data.length);
            },
            onError: (_) {
              cleanupSubscriptions();
              clientSocket.destroy();
              sshChannel.close();
            },
            onDone: () {
              cleanupSubscriptions();
              sshChannel.close();
            },
          );
          _subscriptions[ruleId]?.add(sub1);

          sub2 = sshChannel.stream.listen(
            (data) {
              clientSocket.add(data);
              _addBytes(ruleId, data.length);
            },
            onError: (_) {
              cleanupSubscriptions();
              clientSocket.destroy();
              sshChannel.close();
            },
            onDone: () {
              cleanupSubscriptions();
              clientSocket.destroy();
            },
          );
          _subscriptions[ruleId]?.add(sub2);

          if (cleanedUp) {
            sub2.cancel();
            _subscriptions[ruleId]?.remove(sub2);
          }
        } catch (_) {
          clientSocket.destroy();
        }
      });
    } catch (e) {
      _activeTunnels[ruleId] = ActiveTunnel(
        ruleId: ruleId,
        hostId: hostId,
        type: 'local',
        localPort: localPort,
        remoteHost: remoteHost,
        remotePort: remotePort,
        isActive: false,
        error: e.toString(),
      );
      _notify();
      rethrow;
    }
  }

  /// Start Remote Port Forwarding (-R)
  Future<void> startRemoteForward({
    required String ruleId,
    required String hostId,
    required SSHClient sshClient,
    required int remotePort,
    required String localHost,
    required int localPort,
  }) async {
    await stopTunnel(ruleId);

    try {
      final listener = await sshClient.forwardRemote(
        port: remotePort,
      );
      _remoteListeners[ruleId] = listener;
      _subscriptions[ruleId] = [];

      final active = ActiveTunnel(
        ruleId: ruleId,
        hostId: hostId,
        type: 'remote',
        localPort: localPort,
        remoteHost: localHost,
        remotePort: remotePort,
        isActive: true,
      );

      _activeTunnels[ruleId] = active;
      _notify();

      if (listener != null) {
        final sub = listener.connections.listen((connection) async {
          try {
            final localSocket = await Socket.connect(localHost, localPort);

            StreamSubscription? sub1;
            StreamSubscription? sub2;
            bool cleanedUp = false;

            void cleanupSubscriptions() {
              if (cleanedUp) return;
              cleanedUp = true;
              sub1?.cancel();
              sub2?.cancel();
              if (sub1 != null) {
                _subscriptions[ruleId]?.remove(sub1);
              }
              if (sub2 != null) {
                _subscriptions[ruleId]?.remove(sub2);
              }
            }

            sub1 = localSocket.listen(
              (data) {
                connection.sink.add(data);
                _addBytes(ruleId, data.length);
              },
              onError: (_) {
                cleanupSubscriptions();
                localSocket.destroy();
                connection.close();
              },
              onDone: () {
                cleanupSubscriptions();
                connection.close();
              },
            );
            _subscriptions[ruleId]?.add(sub1);

            sub2 = connection.stream.listen(
              (data) {
                localSocket.add(data);
                _addBytes(ruleId, data.length);
              },
              onError: (_) {
                cleanupSubscriptions();
                localSocket.destroy();
                connection.close();
              },
              onDone: () {
                cleanupSubscriptions();
                localSocket.destroy();
              },
            );
            _subscriptions[ruleId]?.add(sub2);

            if (cleanedUp) {
              sub2.cancel();
              _subscriptions[ruleId]?.remove(sub2);
            }
          } catch (_) {
            connection.close();
          }
        });
        _subscriptions[ruleId]?.add(sub);
      }
    } catch (e) {
      _activeTunnels[ruleId] = ActiveTunnel(
        ruleId: ruleId,
        hostId: hostId,
        type: 'remote',
        localPort: localPort,
        remoteHost: localHost,
        remotePort: remotePort,
        isActive: false,
        error: e.toString(),
      );
      _notify();
      rethrow;
    }
  }

  /// Start Dynamic SOCKS5 Proxy (-D)
  Future<void> startDynamicForward({
    required String ruleId,
    required String hostId,
    required SSHClient sshClient,
    required int localPort,
  }) async {
    await stopTunnel(ruleId);

    try {
      final socksServer = Socks5ProxyServer(
        localPort: localPort,
        sshClient: sshClient,
        onBytesTransferred: (bytes) => _addBytes(ruleId, bytes),
      );

      await socksServer.start();
      _socksServers[ruleId] = socksServer;

      final active = ActiveTunnel(
        ruleId: ruleId,
        hostId: hostId,
        type: 'dynamic',
        localPort: localPort,
        isActive: true,
      );

      _activeTunnels[ruleId] = active;
      _notify();
    } catch (e) {
      _activeTunnels[ruleId] = ActiveTunnel(
        ruleId: ruleId,
        hostId: hostId,
        type: 'dynamic',
        localPort: localPort,
        isActive: false,
        error: e.toString(),
      );
      _notify();
      rethrow;
    }
  }

  /// Stop a specific tunnel by ruleId
  Future<void> stopTunnel(String ruleId) async {
    if (_subscriptions.containsKey(ruleId)) {
      for (final sub in List<StreamSubscription>.from(_subscriptions[ruleId]!)) {
        await sub.cancel();
      }
      _subscriptions.remove(ruleId);
    }

    if (_localServers.containsKey(ruleId)) {
      await _localServers[ruleId]?.close();
      _localServers.remove(ruleId);
    }

    if (_socksServers.containsKey(ruleId)) {
      await _socksServers[ruleId]?.stop();
      _socksServers.remove(ruleId);
    }

    _remoteListeners.remove(ruleId);

    _lastBytesSample.remove(ruleId);
    _lastSampleTime.remove(ruleId);

    if (_activeTunnels.containsKey(ruleId)) {
      _activeTunnels.remove(ruleId);
      _notify();
    }
  }

  /// Stop all active tunnels
  Future<void> stopAllTunnels() async {
    final keys = _activeTunnels.keys.toList();
    for (final ruleId in keys) {
      await stopTunnel(ruleId);
    }
  }

  void _addBytes(String ruleId, int count) {
    if (_activeTunnels.containsKey(ruleId)) {
      final curr = _activeTunnels[ruleId]!;
      _activeTunnels[ruleId] = curr.copyWith(
        bytesTransferred: curr.bytesTransferred + count,
      );
    }
  }

  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeTunnels.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      bool updated = false;

      for (final ruleId in _activeTunnels.keys) {
        final tunnel = _activeTunnels[ruleId]!;
        final lastBytes = _lastBytesSample[ruleId] ?? 0;
        final lastTime = _lastSampleTime[ruleId] ?? (now - 1000);

        final deltaBytes = tunnel.bytesTransferred - lastBytes;
        final deltaTime = now - lastTime;

        int speed = 0;
        if (deltaTime > 0) {
          speed = ((deltaBytes * 1000) / deltaTime).round();
        }

        _lastBytesSample[ruleId] = tunnel.bytesTransferred;
        _lastSampleTime[ruleId] = now;

        if (tunnel.speedBytesPerSec != speed) {
          _activeTunnels[ruleId] = tunnel.copyWith(speedBytesPerSec: speed);
          updated = true;
        }
      }

      if (updated) {
        _notify();
      }
    });
  }

  void _notify() {
    if (!_tunnelsController.isClosed) {
      _tunnelsController.add(activeTunnelsList);
    }
  }

  void dispose() {
    _statsTimer?.cancel();
    stopAllTunnels();
    _tunnelsController.close();
  }
}
