import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_exception.dart';
import 'package:shellvibe/core/api/api_transport.dart';

void main() {
  test('a connection dropped mid-body is a transport failure', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) async {
      await socket.first;
      socket.write('HTTP/1.1 200 OK\r\ncontent-length: 100\r\n\r\npartial');
      await socket.flush();
      socket.destroy();
    });
    final transport = IoApiTransport();
    addTearDown(() async {
      transport.close();
      await server.close();
    });

    await expectLater(
      transport.send(
        ApiRawRequest(
          method: 'GET',
          url: Uri.parse('http://127.0.0.1:${server.port}/x'),
        ),
      ),
      throwsA(isA<ApiTransportException>()),
    );
  });
}
