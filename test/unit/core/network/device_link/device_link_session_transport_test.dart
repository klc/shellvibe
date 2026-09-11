import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/device_link/device_link_attachment.dart';
import 'package:shellvibe/core/network/device_link/device_link_client.dart';
import 'package:shellvibe/core/network/device_link/device_link_identity.dart';
import 'package:shellvibe/core/network/device_link/device_link_local_session_transport.dart';
import 'package:shellvibe/core/network/device_link/device_link_protocol.dart';
import 'package:shellvibe/core/network/device_link/device_link_server.dart';
import 'package:shellvibe/core/network/device_link/device_link_session_transport.dart';
import 'package:shellvibe/core/network/local_pty_manager.dart';
import 'package:xterm3/xterm.dart';
import 'package:shellvibe/core/network/coalescing_terminal_writer.dart';
import 'package:shellvibe/core/network/pty_session.dart';

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
    bridge = TerminalLocalPtyBridge(
      terminal: terminal,
      session: pty,
      // No frame pipeline here, so the write stack hands over off a
      // resolved future instead of waiting for a frame that never comes.
      writerOverride: CoalescingTerminalWriter(
        PacedTerminalWriter(terminal),
        waitForFrame: () async {},
      ),
    );
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
    'attaches a local PTY, routes input, resizes, and shares with the desktop',
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
      await _waitUntil(() => pty.writes.isNotEmpty);
      expect(pty.writes.single, orderedEquals([0x65, 0x63, 0x68, 0x6f, 0x0a]));

      await client.sendResize(const DeviceLinkResize(cols: 70, rows: 18));
      await _waitUntil(
        () => terminal.viewWidth == 70 && terminal.viewHeight == 18,
      );
      expect(terminal.viewWidth, 70);
      expect(terminal.viewHeight, 18);

      // The desktop keeps typing into the same process. That is sharing, not a
      // takeover: the phone stays attached and writable, and the session keeps
      // the dimensions the phone asked for.
      terminal.onOutput?.call('d');
      await pumpEventQueue();
      expect(pty.writes.last, orderedEquals([0x64]));
      expect(client.isReadOnly, isFalse);
      expect(transport.isAttached, isTrue);
      expect(terminal.viewWidth, 70);
      expect(terminal.viewHeight, 18);

      // A reply the desktop terminal makes on its own — a program probing it
      // for device attributes, say — is not the desktop user typing either.
      terminal.write('\x1b[c');
      await pumpEventQueue();
      expect(client.isReadOnly, isFalse);
      expect(transport.isAttached, isTrue);

      // Only an explicit detach ends it.
      await client.sendDetach();
      await _waitUntil(() => !transport.isAttached);
      expect(terminal.viewWidth, 80);
      expect(terminal.viewHeight, 24);
      expect(transport.isAttached, isFalse);
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'the same device reattaching takes its session back',
    () async {
      final first = await _pair(identity, server);
      await first.sendAttach(
        const DeviceLinkAttach(sessionId: 'local-1', cols: 52, rows: 30),
      );
      await first.nextControl(timeout: _timeout);
      await first.nextBinary(timeout: _timeout);
      expect(transport.isAttached, isTrue);

      // The phone comes back on a fresh socket — a rescan, an app restart — while
      // the desktop has not yet noticed the old one is gone. Its own stale
      // attachment must not lock it out of the session it just paired with.
      final again = await _pair(identity, server);
      addTearDown(again.close);
      await again.sendAttach(
        const DeviceLinkAttach(sessionId: 'local-1', cols: 44, rows: 26),
      );

      expect(
        await again.nextControl(timeout: _timeout),
        isA<DeviceLinkAttached>(),
      );
      await again.nextBinary(timeout: _timeout);
      expect(transport.isAttached, isTrue);
      expect(terminal.viewWidth, 44);
      expect(terminal.viewHeight, 26);
      // The dimensions to restore are still the desktop's own, not the ones the
      // retired connection had imposed.
      expect(attachment?.previousColumns, 80);
      expect(attachment?.previousRows, 24);
    },
    timeout: const Timeout(_timeout),
  );

  test('a shell that exits ends the sharing', () async {
    final client = await _pair(identity, server);
    addTearDown(client.close);
    await client.sendAttach(
      const DeviceLinkAttach(sessionId: 'local-1', cols: 52, rows: 30),
    );
    await client.nextControl(timeout: _timeout);
    await client.nextBinary(timeout: _timeout);
    expect(transport.isAttached, isTrue);

    // The phone is attached to a process, not to a window. Exiting the shell
    // disposes the bridge; without a path out of that, the attachment stays —
    // the desktop keeps a "shared" badge whose disconnect button then hits the
    // same dead session and is refused.
    await pty.dispose();
    await _waitUntil(() => !transport.isAttached);

    expect(transport.isAttached, isFalse);
    expect(attachment, isNull);
    expect(terminal.viewWidth, 80);
    expect(terminal.viewHeight, 24);
  }, timeout: const Timeout(_timeout));

  test(
    'detaching still works once the session underneath is gone',
    () async {
      final client = await _pair(identity, server);
      addTearDown(client.close);
      await client.sendAttach(
        const DeviceLinkAttach(sessionId: 'local-1', cols: 52, rows: 30),
      );
      await client.nextControl(timeout: _timeout);
      await client.nextBinary(timeout: _timeout);

      // Kill the bridge without going through the exit path, so the transport
      // still believes it is attached to a session that no longer exists.
      await bridge.dispose();

      await client.sendDetach();
      await _waitUntil(() => !transport.isAttached);

      expect(transport.isAttached, isFalse);
      expect(attachment, isNull);
      expect(terminal.viewWidth, 80);
      expect(terminal.viewHeight, 24);
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'another live device is not thrown off the session',
    () async {
      final owner = await _pair(identity, server, deviceId: 'phone-1');
      addTearDown(owner.close);
      await owner.sendAttach(
        const DeviceLinkAttach(sessionId: 'local-1', cols: 52, rows: 30),
      );
      await owner.nextControl(timeout: _timeout);
      await owner.nextBinary(timeout: _timeout);

      final other = await _pair(identity, server, deviceId: 'phone-2');
      addTearDown(other.close);
      await other.sendAttach(
        const DeviceLinkAttach(sessionId: 'local-1', cols: 44, rows: 26),
      );

      final rejected = await other.nextControl(timeout: _timeout);
      expect(rejected, isA<DeviceLinkError>());
      expect((rejected as DeviceLinkError).code, 'session_in_use');
      // The first phone keeps the session, at its own size.
      expect(terminal.viewWidth, 52);
      expect(terminal.viewHeight, 30);
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
      await _waitUntil(() => !transport.isAttached);
      expect(transport.isAttached, isFalse);
      expect(terminal.viewWidth, 80);
      expect(terminal.viewHeight, 24);
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'disposing the desktop transport closes the owning phone connection',
    () async {
      final client = await _pair(identity, server, deviceId: 'phone-2');
      await client.sendAttach(
        const DeviceLinkAttach(sessionId: 'local-1', cols: 60, rows: 20),
      );
      await client.nextControl(timeout: _timeout);
      await client.nextBinary(timeout: _timeout);

      await transport.dispose();
      await _waitUntil(() => client.isClosed);

      expect(transport.isAttached, isFalse);
      expect(attachment, isNull);
      expect(terminal.viewWidth, 80);
      expect(terminal.viewHeight, 24);
      expect(client.isClosed, isTrue);
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'releases an attachment before reporting an oversized snapshot',
    () async {
      final oversizedTransport = _OversizedSnapshotTransport();
      final oversizedServer = DeviceLinkServer(
        identity: identity,
        hostName: 'test-host',
        appVersion: 'test',
        sessionTransportsProvider: () => [oversizedTransport],
      );
      await oversizedServer.start();
      addTearDown(oversizedServer.close);

      final client = await _pair(identity, oversizedServer);
      addTearDown(client.close);
      await client.sendAttach(
        const DeviceLinkAttach(sessionId: 'oversized', cols: 52, rows: 30),
      );

      final error = await client.nextControl(timeout: _timeout);
      expect(error, isA<DeviceLinkError>());
      expect((error as DeviceLinkError).code, 'snapshot_too_large');
      expect(oversizedTransport.isAttached, isFalse);
      expect(oversizedTransport.detachCalls, 1);
      expect(client.isClosed, isFalse);
      await expectLater(
        client.nextBinary(timeout: const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'releases an attachment when the attached response cannot be encoded',
    () async {
      final failingTransport = _ResponseSendFailureTransport();
      final failingServer = DeviceLinkServer(
        identity: identity,
        hostName: 'test-host',
        appVersion: 'test',
        sessionTransportsProvider: () => [failingTransport],
      );
      await failingServer.start();
      addTearDown(failingServer.close);

      final failedClient = await _pair(identity, failingServer);
      addTearDown(failedClient.close);
      await failedClient.sendAttach(
        const DeviceLinkAttach(sessionId: 'send-failure', cols: 52, rows: 30),
      );

      final error = await failedClient.nextControl(timeout: _timeout);
      expect(error, isA<DeviceLinkError>());
      expect((error as DeviceLinkError).code, 'attach_failed');
      expect(failingTransport.isAttached, isFalse);
      expect(failingTransport.detachCalls, 1);

      final retryClient = await _pair(identity, failingServer);
      addTearDown(retryClient.close);
      await retryClient.sendAttach(
        const DeviceLinkAttach(sessionId: 'send-failure', cols: 52, rows: 30),
      );

      expect(
        await retryClient.nextControl(timeout: _timeout),
        isA<DeviceLinkAttached>(),
      );
      expect(
        (await retryClient.nextBinary(timeout: _timeout)).type,
        DeviceLinkBinaryFrameType.snapshot,
      );
      expect(failingTransport.attachCalls, 2);
      expect(failingTransport.isAttached, isTrue);
    },
    timeout: const Timeout(_timeout),
  );
}

Future<void> _waitUntil(bool Function() condition) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed >= const Duration(seconds: 2)) {
      throw TimeoutException('Timed out waiting for the Device Link state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
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
  await client.nextControl(timeout: _timeout);
  return client;
}

final class FakePty implements PtySession {
  final _outputController = StreamController<Uint8List>();
  final writes = <Uint8List>[];

  @override
  Stream<Uint8List> get output => _outputController.stream;

  @override
  Future<int> get exitCode => Future.value(0);

  @override
  void write(Uint8List data) => writes.add(Uint8List.fromList(data));

  @override
  void resize(int rows, int cols) {}

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  void acknowledge() {}

  void emitOutput(List<int> bytes) {
    _outputController.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> dispose({bool kill = true}) => _outputController.close();
}

final class _OversizedSnapshotTransport implements DeviceLinkSessionTransport {
  @override
  final info = const DeviceLinkSessionInfo(
    id: 'oversized',
    title: 'Oversized snapshot',
    type: 'local',
  );

  bool _attached = false;
  int detachCalls = 0;

  @override
  bool get isAttached => _attached;

  @override
  Future<DeviceLinkSessionAttachResult> attach({
    required DeviceLinkServerConnection connection,
    required DeviceLinkAttach request,
  }) async {
    _attached = true;
    return DeviceLinkSessionAttachResult(
      attached: const DeviceLinkAttached(
        sessionId: 'oversized',
        cols: 52,
        rows: 30,
        alt: false,
        bracketedPaste: false,
        scrollbackLines: 0,
      ),
      snapshotPayload: List<int>.filled(
        deviceLinkMaxSnapshotPayloadLength + 1,
        0,
      ),
    );
  }

  @override
  Future<void> writeInput({
    required DeviceLinkServerConnection connection,
    required Uint8List bytes,
  }) async {}

  @override
  Future<void> resize({
    required DeviceLinkServerConnection connection,
    required int columns,
    required int rows,
  }) async {}

  @override
  Future<DeviceLinkAttachment?> detach({
    required DeviceLinkServerConnection connection,
  }) async {
    _attached = false;
    detachCalls++;
    return null;
  }

  @override
  Future<void> dispose() async {}
}

final class _ResponseSendFailureTransport
    implements DeviceLinkSessionTransport {
  @override
  final info = const DeviceLinkSessionInfo(
    id: 'send-failure',
    title: 'Response send failure',
    type: 'local',
  );

  bool _attached = false;
  int attachCalls = 0;
  int detachCalls = 0;

  @override
  bool get isAttached => _attached;

  @override
  Future<DeviceLinkSessionAttachResult> attach({
    required DeviceLinkServerConnection connection,
    required DeviceLinkAttach request,
  }) async {
    attachCalls++;
    _attached = true;
    return DeviceLinkSessionAttachResult(
      attached: DeviceLinkAttached(
        sessionId: attachCalls == 1 ? 'x' * 65536 : info.id,
        cols: 52,
        rows: 30,
        alt: false,
        bracketedPaste: false,
        scrollbackLines: 0,
      ),
      snapshotPayload: const [],
    );
  }

  @override
  Future<void> writeInput({
    required DeviceLinkServerConnection connection,
    required Uint8List bytes,
  }) async {}

  @override
  Future<void> resize({
    required DeviceLinkServerConnection connection,
    required int columns,
    required int rows,
  }) async {}

  @override
  Future<DeviceLinkAttachment?> detach({
    required DeviceLinkServerConnection connection,
  }) async {
    _attached = false;
    detachCalls++;
    return null;
  }

  @override
  Future<void> dispose() async {}
}
