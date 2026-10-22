// Drives the real stdio bridge (tool/shellvibe_mcp_bridge) against a stand-in
// for the app's HTTP endpoint.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory dir;
  late Process bridge;
  late List<Map<String, dynamic>> frames;
  late StreamController<Map<String, dynamic>> frameEvents;
  late Completer<void> slowGate;

  setUp(() async {
    slowGate = Completer<void>();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      if (!body.containsKey('id')) {
        request.response.statusCode = HttpStatus.accepted;
        await request.response.close();
        return;
      }
      if (body['method'] == 'slow') await slowGate.future;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': {}}),
      );
      await request.response.close();
    });

    dir = await Directory.systemTemp.createTemp('bridge_test');
    final endpoint = File('${dir.path}/mcp-endpoint.json')
      ..writeAsStringSync(jsonEncode({'port': server.port, 'token': 't'}));

    bridge = await Process.start('dart', [
      'run',
      'tool/shellvibe_mcp_bridge/bin/shellvibe_mcp.dart',
      '--endpoint',
      endpoint.path,
    ]);
    frames = [];
    frameEvents = StreamController.broadcast();
    bridge.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .listen((frame) {
          frames.add(frame);
          frameEvents.add(frame);
        });
  });

  tearDown(() async {
    bridge.kill();
    await frameEvents.close();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  Future<void> replyTo(int id) async {
    if (frames.any((f) => f['id'] == id)) return;
    await frameEvents.stream.firstWhere((f) => f['id'] == id);
  }

  void send(Map<String, dynamic> message) =>
      bridge.stdin.writeln(jsonEncode({'jsonrpc': '2.0', ...message}));

  test(
    'a request does not wait behind one still in flight, and a notification '
    'gets no reply',
    () async {
      send({'id': 1, 'method': 'slow'});
      send({'method': 'notifications/initialized'});
      send({'id': 2, 'method': 'fast'});

      // A bridge that relays one request at a time never answers this while
      // `slow` is held open.
      await replyTo(2);
      slowGate.complete();
      await replyTo(1);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(frames.map((f) => f['id']), [2, 1]);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
