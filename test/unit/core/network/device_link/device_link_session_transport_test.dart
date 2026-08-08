import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/core/network/device_link/device_link_attachment.dart';
import 'package:terly2/core/network/device_link/device_link_client.dart';
import 'package:terly2/core/network/device_link/device_link_identity.dart';
import 'package:terly2/core/network/device_link/device_link_local_session_transport.dart';
import 'package:terly2/core/network/device_link/device_link_protocol.dart';
import 'package:terly2/core/network/device_link/device_link_server.dart';
import 'package:terly2/core/network/local_pty_manager.dart';
import 'package:xterm3/xterm.dart';

const _timeout = Duration(seconds: 5);

void main() {
  late FakePty pty;
  late Terminal terminal;
  late TerminalLocalPtyBridge bridge;
  late DeviceLinkIdentity identity;
  late DeviceLinkServer server;
  late DeviceLinkLocalSessionTransport transport;
  DeviceLinkAttachment? attachment;

  setUp(() async {
    pty = FakePty();
    terminal = Terminal();
    terminal.resize(80, 24);
    bridge = TerminalLocalPtyBridge(terminal: terminal, pty: pty);
    attachment = null;
    transport = DeviceLinkLocalSessionTransport(
      sessionId: 'local-1',
      title: 'Local shell',
      terminal: terminal,
      ptyBridge: bridge,
      attachSession: (deviceId, columns, rows) {
        attachment = DeviceLinkAttachment(
          deviceId: deviceId,
          previousColumns: terminal.viewWidth,
          previousRows: terminal.viewHeight,
          attachedAt: DateTime.now().toUtc(),
        );
        terminal.resize(columns, rows);
        return attachment!;
      },
      detachSession: () {
        final previous = attachment;
        attachment = null;
        if (previous != null) {
          terminal.resize(previous.previousColumns, previous.previousRows);
        }
        return previous;
      },
      resizeSession: terminal.resize,
    );
    identity = DeviceLinkIdentity.generate();
    server = DeviceLinkServer(
      identity: identity,
      hostName: 'test-host',
      appVersion: 'test',
      sessionTransportsProvider: () => [transport],
    );
    await server.start();
  });

  tearDown(() async {
    await server.close();
    await bridge.dispose();
  });

  test(
    'attaches a local PTY, routes input, resizes, and restores on reclaim',
    () async {
      final client = await _pair(identity, server);
      addTearDown(client.close);

      await client.sendAttach(
        const DeviceLinkAttach(sessionId: 'local-1', cols: 52, rows: 30),
      );
      final attached = await client.nextControl(timeout: _timeout);
      expect(attached, isA<DeviceLinkAttached>());
      expect(terminal.viewWidth, 52);
      expect(terminal.viewHeight, 30);
      expect(attachment?.deviceId, 'phone-1');
      expect(
        (await client.nextBinary(timeout: _timeout)).type,
        DeviceLinkBinaryFrameType.snapshot,
      );

      pty.emitOutput(const [0x6f, 0x6b, 0x0a]);
      final liveOutput = await client.nextBinary(timeout: _timeout);
      expect(liveOutput.type, DeviceLinkBinaryFrameType.ptyOutput);
      expect(liveOutput.payload, orderedEquals(const [0x6f, 0x6b, 0x0a]));

      await client.sendBinary(
        DeviceLinkBinaryFrame(
          type: DeviceLinkBinaryFrameType.ptyInput,
          payload: [0x65, 0x63, 0x68, 0x6f, 0x0a],
        ),
      );
      await pumpEventQueue();
      expect(pty.writes.single, orderedEquals([0x65, 0x63, 0x68, 0x6f, 0x0a]));

      await client.sendResize(const DeviceLinkResize(cols: 70, rows: 18));
      await pumpEventQueue();
      expect(terminal.viewWidth, 70);
      expect(terminal.viewHeight, 18);

      // The desktop path remains live and reclaims ownership on first input.
      terminal.onOutput?.call('d');
      final reclaimed = await client.nextControl(timeout: _timeout);
      expect(reclaimed, isA<DeviceLinkReclaimed>());
      expect(terminal.viewWidth, 80);
      expect(terminal.viewHeight, 24);
      expect(client.isReadOnly, isTrue);

      await client.sendAttach(
        const DeviceLinkAttach(sessionId: 'local-1', cols: 45, rows: 25),
      );
      expect(
        await client.nextControl(timeout: _timeout),
        isA<DeviceLinkAttached>(),
      );
      await client.nextBinary(timeout: _timeout);
      await client.sendDetach();
      await pumpEventQueue();
      expect(terminal.viewWidth, 80);
      expect(terminal.viewHeight, 24);
      expect(transport.isAttached, isFalse);
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'disconnect restores the desktop dimensions and releases ownership',
    () async {
      final client = await _pair(identity, server, deviceId: 'phone-2');
      await client.sendAttach(
        const DeviceLinkAttach(sessionId: 'local-1', cols: 60, rows: 20),
      );
      await client.nextControl(timeout: _timeout);
      await client.nextBinary(timeout: _timeout);
      expect(transport.isAttached, isTrue);

      await client.close();
      await pumpEventQueue();
      expect(transport.isAttached, isFalse);
      expect(terminal.viewWidth, 80);
      expect(terminal.viewHeight, 24);
    },
    timeout: const Timeout(_timeout),
  );
}

Future<DeviceLinkClientConnection> _pair(
  DeviceLinkIdentity identity,
  DeviceLinkServer server, {
  String deviceId = 'phone-1',
}) async {
  final payload = await server.createPairingPayload(
    addresses: const ['127.0.0.1'],
  );
  final client = await DeviceLinkClient(connectionTimeout: _timeout).connect([
    DeviceLinkEndpoint(
      host: '127.0.0.1',
      port: server.port,
      spkiSha256Base64: identity.spkiSha256Base64,
    ),
  ]);
  await client.sendHello(
    DeviceLinkHello(deviceId: deviceId, deviceName: 'Phone'),
  );
  await client.nextControl(timeout: _timeout);
  await client.sendPair(
    DeviceLinkPair(
      token: payload.token,
      deviceName: 'Phone',
      devicePublicKey: 'phone-public-key',
    ),
  );
  expect(await client.nextControl(timeout: _timeout), isA<DeviceLinkPaired>());
  return client;
}

final class FakePty implements Pty {
  final _outputController = StreamController<Uint8List>();
  final writes = <Uint8List>[];

  @override
  String get executable => '/bin/sh';

  @override
  List<String> get arguments => const [];

  @override
  Stream<Uint8List> get output => _outputController.stream;

  @override
  Future<int> get exitCode => Future.value(0);

  @override
  int get pid => 1234;

  @override
  void write(Uint8List data) => writes.add(Uint8List.fromList(data));

  @override
  void resize(int rows, int cols) {}

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  void ackRead() {}

  void emitOutput(List<int> bytes) {
    _outputController.add(Uint8List.fromList(bytes));
  }

  Future<void> dispose() => _outputController.close();
}
