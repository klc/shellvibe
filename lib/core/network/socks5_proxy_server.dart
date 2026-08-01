import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

typedef BytesTransferredCallback = void Function(int bytes);

/// Pure Dart SOCKS5 Proxy Server for Dynamic Port Forwarding (-D).
class Socks5ProxyServer {
  final int localPort;
  final SSHClient sshClient;
  final String bindAddress;
  final BytesTransferredCallback? onBytesTransferred;

  ServerSocket? _serverSocket;
  final List<StreamSubscription> _activeSubscriptions = [];
  final Set<Socket> _activeSockets = {};
  final Set<SSHForwardChannel> _activeChannels = {};
  bool _isListening = false;

  Socks5ProxyServer({
    required this.localPort,
    required this.sshClient,
    this.bindAddress = '127.0.0.1',
    this.onBytesTransferred,
  });

  bool get isListening => _isListening;

  /// Starts listening for SOCKS5 connections.
  Future<void> start() async {
    _serverSocket = await ServerSocket.bind(bindAddress, localPort);
    _isListening = true;

    _serverSocket!.listen(
      _handleClient,
      onError: (_) {},
      onDone: () {
        _isListening = false;
      },
    );
  }

  Future<void> _handleClient(Socket clientSocket) async {
    _activeSockets.add(clientSocket);
    final reader = _BufferedSocketReader(clientSocket);
    try {
      // Step 1: Handshake
      final handshakeData = await reader.readExact(2);
      if (handshakeData.length < 2 || handshakeData[0] != 0x05) {
        await reader.detach();
        _activeSockets.remove(clientSocket);
        clientSocket.destroy();
        return;
      }

      final nmethods = handshakeData[1];
      final methods = await reader.readExact(nmethods);
      if (methods.length < nmethods) {
        await reader.detach();
        _activeSockets.remove(clientSocket);
        clientSocket.destroy();
        return;
      }

      // Reply: SOCKS5, NO AUTHENTICATION REQUIRED (0x00)
      clientSocket.add([0x05, 0x00]);
      await clientSocket.flush();

      // Step 2: Request Parsing
      final reqHeader = await reader.readExact(4);
      if (reqHeader.length < 4 || reqHeader[0] != 0x05 || reqHeader[1] != 0x01) {
        // Only CMD 0x01 (CONNECT) is supported
        clientSocket.add([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]); // Command not supported
        await clientSocket.flush();
        await reader.detach();
        _activeSockets.remove(clientSocket);
        clientSocket.destroy();
        return;
      }

      final atyp = reqHeader[3];
      String targetHost = '';

      if (atyp == 0x01) {
        // IPv4 (4 bytes)
        final ipv4Bytes = await reader.readExact(4);
        if (ipv4Bytes.length < 4) {
          await reader.detach();
          _activeSockets.remove(clientSocket);
          clientSocket.destroy();
          return;
        }
        targetHost = ipv4Bytes.join('.');
      } else if (atyp == 0x03) {
        // Domain Name (1 byte length + domain string)
        final lenBytes = await reader.readExact(1);
        if (lenBytes.isEmpty) {
          await reader.detach();
          _activeSockets.remove(clientSocket);
          clientSocket.destroy();
          return;
        }
        final domainLen = lenBytes[0];
        final domainBytes = await reader.readExact(domainLen);
        if (domainBytes.length < domainLen) {
          await reader.detach();
          _activeSockets.remove(clientSocket);
          clientSocket.destroy();
          return;
        }
        targetHost = String.fromCharCodes(domainBytes);
      } else if (atyp == 0x04) {
        // IPv6 (16 bytes)
        final ipv6Bytes = await reader.readExact(16);
        if (ipv6Bytes.length < 16) {
          await reader.detach();
          _activeSockets.remove(clientSocket);
          clientSocket.destroy();
          return;
        }
        final segments = <String>[];
        for (int i = 0; i < 16; i += 2) {
          final val = (ipv6Bytes[i] << 8) | ipv6Bytes[i + 1];
          segments.add(val.toRadixString(16));
        }
        targetHost = segments.join(':');
      } else {
        await reader.detach();
        _activeSockets.remove(clientSocket);
        clientSocket.destroy();
        return;
      }

      final portBytes = await reader.readExact(2);
      if (portBytes.length < 2) {
        await reader.detach();
        _activeSockets.remove(clientSocket);
        clientSocket.destroy();
        return;
      }
      final targetPort = (portBytes[0] << 8) | portBytes[1];

      // Step 3: Open SSH channel to destination target
      SSHForwardChannel sshChannel;
      try {
        sshChannel = await sshClient.forwardLocal(targetHost, targetPort);
      } catch (_) {
        try {
          clientSocket.add([0x05, 0x04, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
          await clientSocket.flush();
        } catch (_) {}
        await reader.detach();
        _activeSockets.remove(clientSocket);
        clientSocket.destroy();
        return;
      }
      _activeChannels.add(sshChannel);

      // Detach reader before piping directly from clientSocket
      final unconsumed = await reader.detach();

      // Send SOCKS5 Success Response
      clientSocket.add([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      await clientSocket.flush();

      // Forward any unconsumed bytes received during handshake/request parsing
      if (unconsumed.isNotEmpty) {
        sshChannel.sink.add(unconsumed);
        if (onBytesTransferred != null) {
          onBytesTransferred!(unconsumed.length);
        }
      }

      // Step 4: Pipe data bidirectionally
      StreamSubscription? sub1;
      StreamSubscription? sub2;
      bool cleanedUp = false;

      void cleanupSubscriptions() {
        if (cleanedUp) return;
        cleanedUp = true;
        sub1?.cancel();
        sub2?.cancel();
        if (sub1 != null) {
          _activeSubscriptions.remove(sub1);
        }
        if (sub2 != null) {
          _activeSubscriptions.remove(sub2);
        }
        _activeSockets.remove(clientSocket);
        _activeChannels.remove(sshChannel);
      }

      sub1 = clientSocket.listen(
        (data) {
          sshChannel.sink.add(data);
          if (onBytesTransferred != null) {
            onBytesTransferred!(data.length);
          }
        },
        onError: (_) {
          cleanupSubscriptions();
          clientSocket.destroy();
          sshChannel.close();
        },
        onDone: () {
          cleanupSubscriptions();
          clientSocket.destroy();
          sshChannel.close();
        },
      );
      _activeSubscriptions.add(sub1);

      sub2 = sshChannel.stream.listen(
        (data) {
          clientSocket.add(data);
          if (onBytesTransferred != null) {
            onBytesTransferred!(data.length);
          }
        },
        onError: (_) {
          cleanupSubscriptions();
          clientSocket.destroy();
          sshChannel.close();
        },
        onDone: () {
          cleanupSubscriptions();
          clientSocket.destroy();
          sshChannel.close();
        },
      );
      _activeSubscriptions.add(sub2);

      if (cleanedUp) {
        sub2.cancel();
        _activeSubscriptions.remove(sub2);
      }
    } catch (_) {
      if (_activeChannels.isNotEmpty) {
        // Find channels associated or close all remaining channels in exception
        for (final ch in List<SSHForwardChannel>.from(_activeChannels)) {
          ch.close();
        }
        _activeChannels.clear();
      }
      await reader.detach();
      _activeSockets.remove(clientSocket);
      clientSocket.destroy();
    }
  }

  /// Stops the SOCKS5 proxy server.
  Future<void> stop() async {
    _isListening = false;
    for (final sub in List<StreamSubscription>.from(_activeSubscriptions)) {
      await sub.cancel();
    }
    _activeSubscriptions.clear();

    for (final socket in List<Socket>.from(_activeSockets)) {
      socket.destroy();
    }
    _activeSockets.clear();

    for (final channel in List<SSHForwardChannel>.from(_activeChannels)) {
      channel.close();
    }
    _activeChannels.clear();

    await _serverSocket?.close();
    _serverSocket = null;
  }
}

class _BufferedSocketReader {
  final Socket _socket;
  final BytesBuilder _builder = BytesBuilder();
  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _dataCompleter;
  bool _isDone = false;
  bool _hasError = false;

  _BufferedSocketReader(this._socket) {
    _subscription = _socket.listen(
      (chunk) {
        _builder.add(chunk);
        if (_dataCompleter != null && !_dataCompleter!.isCompleted) {
          _dataCompleter!.complete();
        }
      },
      onError: (_) {
        _hasError = true;
        if (_dataCompleter != null && !_dataCompleter!.isCompleted) {
          _dataCompleter!.complete();
        }
      },
      onDone: () {
        _isDone = true;
        if (_dataCompleter != null && !_dataCompleter!.isCompleted) {
          _dataCompleter!.complete();
        }
      },
    );
  }

  Future<Uint8List> readExact(int count) async {
    while (_builder.length < count && !_isDone && !_hasError) {
      _dataCompleter = Completer<void>();
      await _dataCompleter!.future;
    }

    final bytes = _builder.takeBytes();
    if (bytes.length < count) {
      return bytes;
    }

    if (bytes.length > count) {
      final result = bytes.sublist(0, count);
      _builder.add(Uint8List.sublistView(bytes, count));
      return result;
    }

    return bytes;
  }

  Future<Uint8List> detach() async {
    await _subscription?.cancel();
    _subscription = null;
    return _builder.takeBytes();
  }
}
