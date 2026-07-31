import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/core/network/socks5_proxy_server.dart';

class FakeSSHForwardChannel implements SSHForwardChannel {
  final StreamController<Uint8List> _channelStreamController = StreamController<Uint8List>();
  final StreamController<List<int>> _channelSinkController = StreamController<List<int>>();

  @override
  Stream<Uint8List> get stream => _channelStreamController.stream;

  @override
  StreamSink<List<int>> get sink => _channelSinkController.sink;

  Stream<List<int>> get sinkStream => _channelSinkController.stream;

  @override
  Future<void> close() async {
    await _channelStreamController.close();
    await _channelSinkController.close();
  }

  @override
  void destroy() {}

  @override
  Future<void> get done => _channelStreamController.done;

  @override
  Future<void> flush() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSSHClient implements SSHClient {
  final FakeSSHForwardChannel channel;
  String? lastForwardedHost;
  int? lastForwardedPort;

  FakeSSHClient(this.channel);

  @override
  Future<SSHForwardChannel> forwardLocal(String targetHost, int targetPort, {int localPort = 0, String localHost = 'localhost'}) async {
    lastForwardedHost = targetHost;
    lastForwardedPort = targetPort;
    return channel;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeSSHClient fakeSshClient;
  late FakeSSHForwardChannel fakeChannel;
  late Socks5ProxyServer proxyServer;
  late int serverPort;

  setUp(() async {
    fakeChannel = FakeSSHForwardChannel();
    fakeSshClient = FakeSSHClient(fakeChannel);

    final serverSocket = await ServerSocket.bind('127.0.0.1', 0);
    serverPort = serverSocket.port;
    await serverSocket.close();

    proxyServer = Socks5ProxyServer(
      localPort: serverPort,
      sshClient: fakeSshClient,
    );

    await proxyServer.start();
  });

  tearDown(() async {
    await proxyServer.stop();
  });

  test('Socks5ProxyServer completes handshake and domain CONNECT request when sent in single chunk', () async {
    final clientSocket = await Socket.connect('127.0.0.1', serverPort);

    final receivedBytes = <int>[];
    final socketCompleter = Completer<void>();

    clientSocket.listen((data) {
      receivedBytes.addAll(data);
      if (receivedBytes.length >= 12) {
        if (!socketCompleter.isCompleted) socketCompleter.complete();
      }
    });

    // Send Handshake + Domain Request + Extra payload in ONE chunk
    final domainStr = 'example.com';
    final payload = [
      // Handshake: VER=5, NMETHODS=1, METHOD=0
      0x05, 0x01, 0x00,
      // Request: VER=5, CMD=1, RSV=0, ATYP=3 (Domain)
      0x05, 0x01, 0x00, 0x03,
      domainStr.length,
      ...domainStr.codeUnits,
      0x00, 0x50, // Port 80
      // Initial payload right after SOCKS5 request frame
      0x48, 0x45, 0x4C, 0x4C, 0x4F, // "HELLO"
    ];

    clientSocket.add(payload);
    await clientSocket.flush();

    await socketCompleter.future;

    // Verify SOCKS5 responses received by client
    // Response 1 (Handshake): [0x05, 0x00]
    // Response 2 (Connect Success): [0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
    expect(receivedBytes.sublist(0, 2), equals([0x05, 0x00]));
    expect(receivedBytes.sublist(2, 12), equals([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]));

    // Verify SSH forwarding was requested with correct target
    expect(fakeSshClient.lastForwardedHost, equals('example.com'));
    expect(fakeSshClient.lastForwardedPort, equals(80));

    // Verify extra payload ("HELLO") was buffered and forwarded to SSH channel sink
    final forwardedBytesCompleter = Completer<List<int>>();
    fakeChannel.sinkStream.listen((data) {
      if (!forwardedBytesCompleter.isCompleted) forwardedBytesCompleter.complete(data);
    });

    final forwarded = await forwardedBytesCompleter.future;
    expect(String.fromCharCodes(forwarded), equals('HELLO'));

    await clientSocket.close();
  });

  test('Socks5ProxyServer completes IPv4 CONNECT request correctly across separate chunks', () async {
    final clientSocket = await Socket.connect('127.0.0.1', serverPort);

    final receivedBytes = <int>[];
    final socketCompleter = Completer<void>();

    clientSocket.listen((data) {
      receivedBytes.addAll(data);
      if (receivedBytes.length >= 12) {
        if (!socketCompleter.isCompleted) socketCompleter.complete();
      }
    });

    // Send Handshake
    clientSocket.add([0x05, 0x01, 0x00]);
    await clientSocket.flush();

    // Send IPv4 Request (127.0.0.1:8080)
    clientSocket.add([
      0x05, 0x01, 0x00, 0x01, // VER=5, CMD=1, RSV=0, ATYP=1 (IPv4)
      127, 0, 0, 1,           // IP
      0x1F, 0x90,             // Port 8080
    ]);
    await clientSocket.flush();

    await socketCompleter.future;

    expect(receivedBytes.sublist(0, 2), equals([0x05, 0x00]));
    expect(receivedBytes.sublist(2, 12), equals([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]));

    expect(fakeSshClient.lastForwardedHost, equals('127.0.0.1'));
    expect(fakeSshClient.lastForwardedPort, equals(8080));

    await clientSocket.close();
  });

  test('Socks5ProxyServer completes IPv6 CONNECT request correctly', () async {
    final clientSocket = await Socket.connect('127.0.0.1', serverPort);

    final receivedBytes = <int>[];
    final socketCompleter = Completer<void>();

    clientSocket.listen((data) {
      receivedBytes.addAll(data);
      if (receivedBytes.length >= 12) {
        if (!socketCompleter.isCompleted) socketCompleter.complete();
      }
    });

    // Send Handshake
    clientSocket.add([0x05, 0x01, 0x00]);
    await clientSocket.flush();

    // Send IPv6 Request (::1 : 443)
    final ipv6Bytes = [
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
    ];
    clientSocket.add([
      0x05, 0x01, 0x00, 0x04, // VER=5, CMD=1, RSV=0, ATYP=4 (IPv6)
      ...ipv6Bytes,
      0x01, 0xBB,             // Port 443
    ]);
    await clientSocket.flush();

    await socketCompleter.future;

    expect(receivedBytes.sublist(0, 2), equals([0x05, 0x00]));
    expect(receivedBytes.sublist(2, 12), equals([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]));

    expect(fakeSshClient.lastForwardedHost, equals('0:0:0:0:0:0:0:1'));
    expect(fakeSshClient.lastForwardedPort, equals(443));

    await clientSocket.close();
  });
}
