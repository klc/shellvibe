import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/core/network/device_link/device_link_client.dart';
import 'package:terly2/core/network/device_link/device_link_identity.dart';
import 'package:terly2/core/network/device_link/device_link_protocol.dart';
import 'package:terly2/core/network/device_link/device_link_server.dart';

const _timeout = Duration(seconds: 5);

void main() {
  late DeviceLinkIdentity identity;
  late DeviceLinkServer server;
  late DeviceLinkBinaryFrame? receivedFrame;

  setUp(() async {
    identity = DeviceLinkIdentity.generate();
    receivedFrame = null;
    server = DeviceLinkServer(
      identity: identity,
      hostName: 'test-host',
      appVersion: 'test',
      sessionsProvider: () async => const [
        DeviceLinkSessionInfo(id: 'local-1', title: 'Shell', type: 'local'),
      ],
      onBinaryFrame: (connection, frame) async {
        receivedFrame = frame;
        await connection.sendBinary(
          DeviceLinkBinaryFrame(
            type: DeviceLinkBinaryFrameType.ptyOutput,
            payload: frame.payload,
          ),
        );
      },
    );
    await server.start();
  });

  tearDown(() => server.close());

  test(
    'accepts a correctly pinned TLS connection and hello/pair flow',
    () async {
      final payload = await server.createPairingPayload(
        addresses: const ['127.0.0.1'],
      );
      final connection = await _connect(identity, server.port);
      addTearDown(connection.close);

      await connection.sendHello(
        const DeviceLinkHello(deviceId: 'phone-1', deviceName: 'Phone'),
      );
      final unauthenticatedHello = await connection.nextControl(
        timeout: _timeout,
      );
      expect(unauthenticatedHello, isA<DeviceLinkHelloAck>());
      expect((unauthenticatedHello as DeviceLinkHelloAck).sessions, isEmpty);

      await connection.sendPair(
        DeviceLinkPair(
          token: payload.token,
          deviceName: 'Phone',
          devicePublicKey: 'phone-public-key',
        ),
      );
      final paired = await connection.nextControl(timeout: _timeout);
      expect(paired, isA<DeviceLinkPaired>());
      expect((paired as DeviceLinkPaired).secret, isNotEmpty);
      final authenticatedHello = await connection.nextControl(
        timeout: _timeout,
      );
      expect(authenticatedHello, isA<DeviceLinkHelloAck>());
      expect(
        (authenticatedHello as DeviceLinkHelloAck).sessions.single.id,
        'local-1',
      );
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'rejects a wrong SPKI pin against the live server',
    () async {
      expect(
        () => DeviceLinkClient(connectionTimeout: _timeout).connect([
          DeviceLinkEndpoint(
            host: '127.0.0.1',
            port: server.port,
            spkiSha256Base64: 'wrong-pin',
          ),
        ]),
        throwsA(isA<DeviceLinkTransportException>()),
      );
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'races candidates and uses the first pinned endpoint that succeeds',
    () async {
      final connection = await DeviceLinkClient(connectionTimeout: _timeout)
          .connect([
            DeviceLinkEndpoint(
              host: '127.0.0.1',
              port: server.port + 1,
              spkiSha256Base64: identity.spkiSha256Base64,
            ),
            DeviceLinkEndpoint(
              host: '127.0.0.1',
              port: server.port,
              spkiSha256Base64: identity.spkiSha256Base64,
            ),
          ]);
      expect(connection.isClosed, isFalse);
      await connection.close();
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'prefers a diagnostic TLS failure over a fast refused endpoint',
    () async {
      late DeviceLinkTransportException failure;
      try {
        await DeviceLinkClient(connectionTimeout: _timeout).connect([
          DeviceLinkEndpoint(
            host: '127.0.0.1',
            port: server.port + 1,
            spkiSha256Base64: identity.spkiSha256Base64,
          ),
          DeviceLinkEndpoint(
            host: '127.0.0.1',
            port: server.port,
            spkiSha256Base64: 'wrong-pin',
          ),
        ]);
        fail('Expected all Device Link endpoints to fail');
      } on DeviceLinkTransportException catch (error) {
        failure = error;
      }

      expect(failure.cause, isA<DeviceLinkTransportException>());
      final selected = failure.cause! as DeviceLinkTransportException;
      expect(selected.cause, isNot(isA<SocketException>()));
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'rejects wrong and second-use pairing tokens',
    () async {
      final payload = await server.createPairingPayload(
        addresses: const ['127.0.0.1'],
      );
      final connection = await _connect(identity, server.port);
      addTearDown(connection.close);
      await connection.sendHello(
        const DeviceLinkHello(deviceId: 'phone-2', deviceName: 'Phone'),
      );
      await connection.nextControl(timeout: _timeout);

      await connection.sendPair(
        const DeviceLinkPair(
          token: 'wrong-token',
          deviceName: 'Phone',
          devicePublicKey: 'phone-public-key',
        ),
      );
      expect(
        await connection.nextControl(timeout: _timeout),
        isA<DeviceLinkError>(),
      );

      await connection.sendPair(
        DeviceLinkPair(
          token: payload.token,
          deviceName: 'Phone',
          devicePublicKey: 'phone-public-key',
        ),
      );
      expect(
        await connection.nextControl(timeout: _timeout),
        isA<DeviceLinkPaired>(),
      );
      await connection.nextControl(timeout: _timeout);

      await connection.sendPair(
        DeviceLinkPair(
          token: payload.token,
          deviceName: 'Phone',
          devicePublicKey: 'phone-public-key',
        ),
      );
      final secondUse = await connection.nextControl(timeout: _timeout);
      expect(
        secondUse is DeviceLinkError &&
            secondUse.code == 'pairing_token_invalid',
        isTrue,
      );
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'rejects expired token and protocol version mismatch',
    () async {
      final expired = await server.createPairingPayload(
        addresses: const ['127.0.0.1'],
        now: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
      );
      expect(server.pairingTokens.consume(expired.token), isFalse);

      final connection = await _connect(identity, server.port);
      addTearDown(connection.close);
      await connection.sendRawText(
        '{"t":"hello","v":${deviceLinkProtocolVersion + 1}}',
      );
      final versionError = await connection.nextControl(timeout: _timeout);
      expect(
        versionError is DeviceLinkError &&
            versionError.code == 'unsupported_version',
        isTrue,
      );
    },
    timeout: const Timeout(_timeout),
  );

  test('rejects binary frames before pairing', () async {
    final connection = await _connect(identity, server.port);
    addTearDown(connection.close);
    await connection.sendHello(
      const DeviceLinkHello(deviceId: 'phone-unpaired', deviceName: 'Phone'),
    );
    await connection.nextControl(timeout: _timeout);

    await connection.sendBinary(
      DeviceLinkBinaryFrame(
        type: DeviceLinkBinaryFrameType.ptyInput,
        payload: [0x65, 0x63, 0x68, 0x6f],
      ),
    );
    final error = await connection.nextControl(timeout: _timeout);
    expect(error is DeviceLinkError && error.code == 'unauthorized', isTrue);
    expect(receivedFrame, isNull);

    await connection.sendAttach(
      const DeviceLinkAttach(sessionId: 'session-1', cols: 80, rows: 24),
    );
    final attachError = await connection.nextControl(timeout: _timeout);
    expect(
      attachError is DeviceLinkError && attachError.code == 'unauthorized',
      isTrue,
    );
  }, timeout: const Timeout(_timeout));

  test(
    'round-trips raw binary frames without UTF-8 conversion',
    () async {
      final payload = await server.createPairingPayload(
        addresses: const ['127.0.0.1'],
      );
      final connection = await _connect(identity, server.port);
      addTearDown(connection.close);
      await connection.sendHello(
        const DeviceLinkHello(deviceId: 'phone-3', deviceName: 'Phone'),
      );
      await connection.nextControl(timeout: _timeout);
      await connection.sendPair(
        DeviceLinkPair(
          token: payload.token,
          deviceName: 'Phone',
          devicePublicKey: 'phone-public-key',
        ),
      );
      expect(
        await connection.nextControl(timeout: _timeout),
        isA<DeviceLinkPaired>(),
      );

      const bytes = [0x00, 0xFF, 0xC3, 0x28];
      await connection.sendBinary(
        DeviceLinkBinaryFrame(
          type: DeviceLinkBinaryFrameType.ptyInput,
          payload: bytes,
        ),
      );
      final echoed = await connection.nextBinary(timeout: _timeout);
      expect(receivedFrame?.type, DeviceLinkBinaryFrameType.ptyInput);
      expect(receivedFrame?.payload, orderedEquals(bytes));
      expect(echoed.type, DeviceLinkBinaryFrameType.ptyOutput);
      expect(echoed.payload, orderedEquals(bytes));
    },
    timeout: const Timeout(_timeout),
  );
}

Future<DeviceLinkClientConnection> _connect(
  DeviceLinkIdentity identity,
  int port,
) {
  return DeviceLinkClient(connectionTimeout: _timeout).connect([
    DeviceLinkEndpoint(
      host: '127.0.0.1',
      port: port,
      spkiSha256Base64: identity.spkiSha256Base64,
    ),
  ]);
}
