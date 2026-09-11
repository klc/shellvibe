import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/device_link/device_link_client.dart';
import 'package:shellvibe/core/network/device_link/device_link_identity.dart';
import 'package:shellvibe/core/network/device_link/device_link_protocol.dart';
import 'package:shellvibe/core/network/device_link/device_link_server.dart';

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
        if (frame.payload.length == 1 && frame.payload.first == 0xFE) {
          await connection.sendBinary(
            DeviceLinkBinaryFrame(
              type: DeviceLinkBinaryFrameType.ptyOutput,
              payload: List<int>.filled(
                deviceLinkMaxPtyOutputPayloadLength + 1,
                0,
              ),
            ),
          );
          return;
        }
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

  test('automatic QR addresses match the default IPv4 bind family', () async {
    final payload = await server.createPairingPayload();

    expect(
      payload.addresses.every(
        (address) =>
            InternetAddress.tryParse(address)?.type == InternetAddressType.IPv4,
      ),
      isTrue,
    );
  });

  test('an IPv6 wildcard bind still advertises IPv4 candidates', () async {
    // Binding the IPv6 wildcard is dual-stack, so dropping the IPv4 addresses
    // would strip the QR of the candidates most home networks actually route.
    final dualStack = DeviceLinkServer(
      identity: identity,
      hostName: 'test-host',
      appVersion: 'test',
      bindAddress: InternetAddress.anyIPv6,
      sessionsProvider: () async => const [],
    );
    await dualStack.start();
    addTearDown(dualStack.close);

    final payload = await dualStack.createPairingPayload();
    final families = payload.addresses
        .map((address) => InternetAddress.tryParse(address)?.type)
        .toSet();

    expect(families, isNot(contains(null)));
    expect(
      families.length > 1 || families.contains(InternetAddressType.IPv4),
      isTrue,
      reason: 'IPv4 candidates must survive a dual-stack bind: $families',
    );
  });

  test(
    'explicit QR addresses are preserved without family filtering',
    () async {
      final payload = await server.createPairingPayload(
        addresses: const ['192.168.1.20', 'fe80::20'],
      );

      expect(payload.addresses, ['192.168.1.20', 'fe80::20']);
    },
  );

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
    'retires only the superseded rows a phone can authenticate',
    () async {
      // Stands in for the desktop's paired-device table: the phone proves an
      // old id was its own by presenting the secret this desktop issued for it.
      final stored = <String, String>{
        'phone-old': 'old-secret',
        'other-phone': 'other-secret',
      };
      final removed = <String>[];
      final persisted = DeviceLinkServer(
        identity: identity,
        hostName: 'test-host',
        appVersion: 'test',
        sessionsProvider: () async => const [],
        pairedDeviceAuthenticator: (deviceId, secret) =>
            stored[deviceId] == secret,
        pairedDevicePersister: (record) => stored[record.id] = record.secret,
        pairedDeviceRemover: (deviceId) {
          stored.remove(deviceId);
          removed.add(deviceId);
        },
      );
      await persisted.start();
      addTearDown(persisted.close);

      final payload = await persisted.createPairingPayload(
        addresses: const ['127.0.0.1'],
      );
      final connection = await _connect(identity, persisted.port);
      addTearDown(connection.close);

      await connection.sendHello(
        const DeviceLinkHello(deviceId: 'phone-new', deviceName: 'Phone'),
      );
      await connection.nextControl(timeout: _timeout);
      await connection.sendPair(
        DeviceLinkPair(
          token: payload.token,
          deviceName: 'Phone',
          devicePublicKey: 'phone-public-key',
          supersedes: const [
            DeviceLinkSupersededDevice(
              deviceId: 'phone-old',
              secret: 'old-secret',
            ),
            // Another phone's row, claimed with a secret this peer never held.
            DeviceLinkSupersededDevice(
              deviceId: 'other-phone',
              secret: 'guessed-secret',
            ),
          ],
        ),
      );

      expect(
        await connection.nextControl(timeout: _timeout),
        isA<DeviceLinkPaired>(),
      );
      expect(
        await connection.nextControl(timeout: _timeout),
        isA<DeviceLinkHelloAck>(),
      );
      expect(removed, ['phone-old']);
      expect(stored.keys, containsAll(<String>['phone-new', 'other-phone']));
      expect(stored.containsKey('phone-old'), isFalse);
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'a retired device id can no longer authenticate a hello',
    () async {
      final firstPayload = await server.createPairingPayload(
        addresses: const ['127.0.0.1'],
      );
      final first = await _connect(identity, server.port);
      addTearDown(first.close);
      await first.sendHello(
        const DeviceLinkHello(deviceId: 'phone-old', deviceName: 'Phone'),
      );
      await first.nextControl(timeout: _timeout);
      await first.sendPair(
        DeviceLinkPair(
          token: firstPayload.token,
          deviceName: 'Phone',
          devicePublicKey: 'phone-public-key',
        ),
      );
      final paired = await first.nextControl(timeout: _timeout);
      final oldSecret = (paired as DeviceLinkPaired).secret;
      await first.nextControl(timeout: _timeout);
      await first.close();

      final secondPayload = await server.createPairingPayload(
        addresses: const ['127.0.0.1'],
      );
      final second = await _connect(identity, server.port);
      addTearDown(second.close);
      await second.sendHello(
        const DeviceLinkHello(deviceId: 'phone-new', deviceName: 'Phone'),
      );
      await second.nextControl(timeout: _timeout);
      await second.sendPair(
        DeviceLinkPair(
          token: secondPayload.token,
          deviceName: 'Phone',
          devicePublicKey: 'phone-public-key',
          supersedes: [
            DeviceLinkSupersededDevice(
              deviceId: 'phone-old',
              secret: oldSecret,
            ),
          ],
        ),
      );
      await second.nextControl(timeout: _timeout);
      await second.nextControl(timeout: _timeout);

      final retired = await _connect(identity, server.port);
      addTearDown(retired.close);
      await retired.sendHello(
        DeviceLinkHello(
          deviceId: 'phone-old',
          deviceName: 'Phone',
          secret: oldSecret,
        ),
      );
      final rejected = await retired.nextControl(timeout: _timeout);
      expect(
        rejected is DeviceLinkError && rejected.code == 'unauthorized',
        isTrue,
      );
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
        DeviceLinkPair(
          token: 'wrong-token',
          deviceName: 'Phone',
          devicePublicKey: 'phone-public-key',
        ),
      );
      expect(
        await connection.nextControl(timeout: _timeout),
        isA<DeviceLinkError>(),
      );
      expect(connection.isClosed, isFalse);

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
    'reports and closes after oversized inbound text and binary frames',
    () async {
      final connection = await _connect(identity, server.port);
      addTearDown(connection.close);

      await connection.sendRawText('x' * (deviceLinkMaxControlFrameLength + 1));
      final textError = await connection.nextControl(timeout: _timeout);
      expect(textError, isA<DeviceLinkError>());
      expect((textError as DeviceLinkError).code, 'frame_too_large');
      expect(receivedFrame, isNull);
      await _waitForClosed(connection);

      final binaryConnection = await _connect(identity, server.port);
      addTearDown(binaryConnection.close);
      final binaryPayload = await server.createPairingPayload(
        addresses: const ['127.0.0.1'],
      );
      await _pair(binaryConnection, binaryPayload.token, 'phone-oversized');
      final oversizedBinaryFrame = Uint8List(
        deviceLinkMaxPtyInputPayloadLength + 2,
      );
      oversizedBinaryFrame[0] = DeviceLinkBinaryFrameType.ptyInput.prefix;
      await binaryConnection.sendRawBinary(oversizedBinaryFrame);
      final binaryError = await binaryConnection.nextControl(timeout: _timeout);
      expect(binaryError, isA<DeviceLinkError>());
      expect((binaryError as DeviceLinkError).code, 'frame_too_large');
      expect(receivedFrame, isNull);
      await _waitForClosed(binaryConnection);
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'closes when the server sends an oversized inbound frame',
    () async {
      final payload = await server.createPairingPayload(
        addresses: const ['127.0.0.1'],
      );
      final connection = await _connect(identity, server.port);
      addTearDown(connection.close);
      await _pair(connection, payload.token, 'phone-malicious-server');

      await connection.sendBinary(
        DeviceLinkBinaryFrame(
          type: DeviceLinkBinaryFrameType.ptyInput,
          payload: [0xFE],
        ),
      );
      for (var i = 0; i < 20 && !connection.isClosed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(connection.isClosed, isTrue);
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'closes after every malformed server text or binary frame',
    () async {
      for (final scenario in <({Object response, String code})>[
        (response: '{', code: 'invalid_json'),
        (response: Uint8List(0), code: 'empty_binary_frame'),
        (
          response: Uint8List.fromList([0xFF]),
          code: 'unknown_binary_frame_type',
        ),
        (response: '{"v":1,"t":"unknown"}', code: 'unknown_message_type'),
      ]) {
        final rawServer = await _startRawServer(identity, scenario.response);
        addTearDown(rawServer.close);
        final connection = await _connect(identity, rawServer.port);
        addTearDown(connection.close);
        final controlErrors = <Object>[];
        final binaryErrors = <Object>[];
        final controlSubscription = connection.controlMessages.listen(
          (_) {},
          onError: (Object error, StackTrace _) => controlErrors.add(error),
        );
        final binarySubscription = connection.binaryFrames.listen(
          (_) {},
          onError: (Object error, StackTrace _) => binaryErrors.add(error),
        );
        addTearDown(controlSubscription.cancel);
        addTearDown(binarySubscription.cancel);

        await connection.sendRawText('trigger');
        await _waitForClosed(connection);

        final errors = scenario.response is List<int>
            ? binaryErrors
            : controlErrors;
        final otherErrors = scenario.response is List<int>
            ? controlErrors
            : binaryErrors;
        expect(errors, hasLength(1));
        expect(otherErrors, isEmpty);
        expect(errors.single, isA<DeviceLinkProtocolException>());
        expect(
          (errors.single as DeviceLinkProtocolException).code,
          scenario.code,
        );
      }
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'delivers malformed control and binary frames to their pending waiters',
    () async {
      final rawControlServer = await _startRawServer(identity, '{');
      addTearDown(rawControlServer.close);
      final controlConnection = await _connect(identity, rawControlServer.port);
      addTearDown(controlConnection.close);
      await controlConnection.sendRawText('trigger');
      await expectLater(
        controlConnection.nextControl(timeout: _timeout),
        throwsA(
          predicate<DeviceLinkProtocolException>(
            (error) => error.code == 'invalid_json',
          ),
        ),
      );
      await _waitForClosed(controlConnection);

      final rawBinaryServer = await _startRawServer(identity, Uint8List(0));
      addTearDown(rawBinaryServer.close);
      final binaryConnection = await _connect(identity, rawBinaryServer.port);
      addTearDown(binaryConnection.close);
      await binaryConnection.sendRawText('trigger');
      await expectLater(
        binaryConnection.nextBinary(timeout: _timeout),
        throwsA(
          predicate<DeviceLinkProtocolException>(
            (error) => error.code == 'empty_binary_frame',
          ),
        ),
      );
      await _waitForClosed(binaryConnection);
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'delivers a malformed binary protocol error to a pending control waiter',
    () async {
      final rawServer = await _startRawServer(
        identity,
        Uint8List.fromList([0xFF]),
      );
      addTearDown(rawServer.close);
      final connection = await _connect(identity, rawServer.port);
      addTearDown(connection.close);

      final controlFuture = connection.nextControl(timeout: _timeout);
      final binaryFuture = connection.nextBinary(timeout: _timeout);
      await connection.sendRawText('trigger');

      final controlExpectation = expectLater(
        controlFuture,
        throwsA(
          predicate<DeviceLinkProtocolException>(
            (error) => error.code == 'unknown_binary_frame_type',
          ),
        ),
      );
      final binaryExpectation = expectLater(
        binaryFuture,
        throwsA(
          predicate<DeviceLinkProtocolException>(
            (error) => error.code == 'unknown_binary_frame_type',
          ),
        ),
      );
      await Future.wait([controlExpectation, binaryExpectation]);
      await _waitForClosed(connection);
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'returns connection_closed immediately for waiters created after close',
    () async {
      final connection = await _connect(identity, server.port);
      await connection.close();

      await expectLater(
        connection.nextControl(timeout: const Duration(seconds: 10)),
        throwsA(
          predicate<DeviceLinkTransportException>(
            (error) => error.code == 'connection_closed',
          ),
        ),
      );
      await expectLater(
        connection.nextBinary(timeout: const Duration(seconds: 10)),
        throwsA(
          predicate<DeviceLinkTransportException>(
            (error) => error.code == 'connection_closed',
          ),
        ),
      );
    },
    timeout: const Timeout(_timeout),
  );

  test(
    'reports and closes when an outbound control frame exceeds the limit',
    () async {
      final oversizedServer = DeviceLinkServer(
        identity: identity,
        hostName: 'test-host',
        appVersion: 'test',
        sessionsProvider: () async => [
          DeviceLinkSessionInfo(
            id: 'local-1',
            title: 'x' * deviceLinkMaxControlFrameLength,
            type: 'local',
          ),
        ],
      );
      await oversizedServer.start();
      addTearDown(oversizedServer.close);

      final payload = await oversizedServer.createPairingPayload(
        addresses: const ['127.0.0.1'],
      );
      final connection = await _connect(identity, oversizedServer.port);
      addTearDown(connection.close);
      await connection.sendHello(
        const DeviceLinkHello(
          deviceId: 'phone-large-control',
          deviceName: 'Phone',
        ),
      );
      expect(
        await connection.nextControl(timeout: _timeout),
        isA<DeviceLinkHelloAck>(),
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

      final error = await connection.nextControl(timeout: _timeout);
      expect(error, isA<DeviceLinkError>());
      expect((error as DeviceLinkError).code, 'frame_too_large');
      await _waitForClosed(connection);
    },
    timeout: const Timeout(_timeout),
  );

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

  test(
    'messages that arrive before anyone listens are not lost',
    () async {
      final payload = await server.createPairingPayload(
        addresses: const ['127.0.0.1'],
      );
      final connection = await _connect(identity, server.port);
      addTearDown(connection.close);
      await connection.sendHello(
        const DeviceLinkHello(deviceId: 'phone-4', deviceName: 'Phone'),
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

      // The pairing flow leaves the socket unattended between the session picker
      // and the linked screen's first frame. Whatever lands in that gap — the
      // post-pairing hello_ack here, an attach result or an error in the real
      // flow — has to reach the subscriber that arrives afterwards.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final received = <DeviceLinkControlMessage>[];
      final subscription = connection.controlMessages.listen(received.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(received, isNotEmpty);
      expect(received.first, isA<DeviceLinkHelloAck>());
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

Future<void> _pair(
  DeviceLinkClientConnection connection,
  String token,
  String deviceId,
) async {
  await connection.sendHello(
    DeviceLinkHello(deviceId: deviceId, deviceName: 'Phone'),
  );
  await connection.nextControl(timeout: _timeout);
  await connection.sendPair(
    DeviceLinkPair(
      token: token,
      deviceName: 'Phone',
      devicePublicKey: 'phone-public-key',
    ),
  );
  expect(
    await connection.nextControl(timeout: _timeout),
    isA<DeviceLinkPaired>(),
  );
  await connection.nextControl(timeout: _timeout);
}

Future<void> _waitForClosed(DeviceLinkClientConnection connection) async {
  final deadline = DateTime.now().add(_timeout);
  while (!connection.isClosed && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(connection.isClosed, isTrue);
}

Future<HttpServer> _startRawServer(
  DeviceLinkIdentity identity,
  Object response,
) async {
  final rawServer = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    identity.createServerSecurityContext(),
  );
  rawServer.listen((request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen((_) async {
      socket.add(response);
      await socket.close();
    });
  });
  return rawServer;
}
