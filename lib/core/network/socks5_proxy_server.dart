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
    try {
      // Step 1: Handshake
      final handshakeData = await _readExactBytes(clientSocket, 2);
      if (handshakeData.length < 2 || handshakeData[0] != 0x05) {
        clientSocket.destroy();
        return;
      }

      final nmethods = handshakeData[1];
      final methods = await _readExactBytes(clientSocket, nmethods);
      if (methods.length < nmethods) {
        clientSocket.destroy();
        return;
      }

      // Reply: SOCKS5, NO AUTHENTICATION REQUIRED (0x00)
      clientSocket.add([0x05, 0x00]);
      await clientSocket.flush();

      // Step 2: Request Parsing
      final reqHeader = await _readExactBytes(clientSocket, 4);
      if (reqHeader.length < 4 || reqHeader[0] != 0x05 || reqHeader[1] != 0x01) {
        // Only CMD 0x01 (CONNECT) is supported
        clientSocket.add([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]); // Command not supported
        await clientSocket.flush();
        clientSocket.destroy();
        return;
      }

      final atyp = reqHeader[3];
      String targetHost = '';

      if (atyp == 0x01) {
        // IPv4 (4 bytes)
        final ipv4Bytes = await _readExactBytes(clientSocket, 4);
        targetHost = ipv4Bytes.join('.');
      } else if (atyp == 0x03) {
        // Domain Name (1 byte length + domain string)
        final lenBytes = await _readExactBytes(clientSocket, 1);
        if (lenBytes.isEmpty) {
          clientSocket.destroy();
          return;
        }
        final domainLen = lenBytes[0];
        final domainBytes = await _readExactBytes(clientSocket, domainLen);
        targetHost = String.fromCharCodes(domainBytes);
      } else if (atyp == 0x04) {
        // IPv6 (16 bytes)
        final ipv6Bytes = await _readExactBytes(clientSocket, 16);
        final segments = <String>[];
        for (int i = 0; i < 16; i += 2) {
          final val = (ipv6Bytes[i] << 8) | ipv6Bytes[i + 1];
          segments.add(val.toRadixString(16));
        }
        targetHost = segments.join(':');
      } else {
        clientSocket.destroy();
        return;
      }

      final portBytes = await _readExactBytes(clientSocket, 2);
      if (portBytes.length < 2) {
        clientSocket.destroy();
        return;
      }
      final targetPort = (portBytes[0] << 8) | portBytes[1];

      // Step 3: Open SSH channel to destination target
      final sshChannel = await sshClient.forwardLocal(targetHost, targetPort);

      // Send SOCKS5 Success Response
      clientSocket.add([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      await clientSocket.flush();

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
        },
      );
      _activeSubscriptions.add(sub2);

      if (cleanedUp) {
        sub2.cancel();
        _activeSubscriptions.remove(sub2);
      }
    } catch (_) {
      clientSocket.destroy();
    }
  }

  Future<Uint8List> _readExactBytes(Socket socket, int count) async {
    final completer = Completer<Uint8List>();
    final builder = BytesBuilder();

    late StreamSubscription sub;
    sub = socket.listen(
      (chunk) {
        builder.add(chunk);
        if (builder.length >= count) {
          sub.cancel();
          completer.complete(builder.takeBytes());
        }
      },
      onError: (_) {
        sub.cancel();
        if (!completer.isCompleted) completer.complete(Uint8List(0));
      },
      onDone: () {
        sub.cancel();
        if (!completer.isCompleted) completer.complete(builder.takeBytes());
      },
    );

    return completer.future;
  }

  /// Stops the SOCKS5 proxy server.
  Future<void> stop() async {
    _isListening = false;
    for (final sub in List<StreamSubscription>.from(_activeSubscriptions)) {
      await sub.cancel();
    }
    _activeSubscriptions.clear();
    await _serverSocket?.close();
    _serverSocket = null;
  }
}
