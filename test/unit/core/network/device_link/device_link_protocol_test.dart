import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/core/network/device_link/device_link_protocol.dart';

void main() {
  group('DeviceLinkControlMessage', () {
    test('round-trips hello with an optional secret', () {
      const original = DeviceLinkHello(
        deviceId: 'phone-1',
        deviceName: 'iPhone 15',
        secret: 'secret-value',
      );

      final decoded = DeviceLinkControlMessage.decode(original.encode());

      expect(decoded, isA<DeviceLinkHello>());
      final hello = decoded as DeviceLinkHello;
      expect(hello.deviceId, original.deviceId);
      expect(hello.deviceName, original.deviceName);
      expect(hello.secret, original.secret);
    });

    test('round-trips hello_ack session descriptors', () {
      final original = DeviceLinkHelloAck(
        appVersion: '1.0.0',
        sessions: const [
          DeviceLinkSessionInfo(
            id: 'session-1',
            title: 'zsh — ~/www/terly2',
            type: 'local',
          ),
        ],
      );

      final decoded = DeviceLinkControlMessage.decode(original.encode());

      expect(decoded, isA<DeviceLinkHelloAck>());
      final ack = decoded as DeviceLinkHelloAck;
      expect(ack.appVersion, '1.0.0');
      expect(ack.sessions.single.id, 'session-1');
      expect(ack.sessions.single.title, 'zsh — ~/www/terly2');
    });

    test(
      'round-trips attach, attached, resize, detach, reclaimed and error',
      () {
        final messages = <DeviceLinkControlMessage>[
          const DeviceLinkAttach(sessionId: 'session-1', cols: 52, rows: 30),
          const DeviceLinkAttached(
            sessionId: 'session-1',
            cols: 52,
            rows: 30,
            alt: false,
            bracketedPaste: true,
            scrollbackLines: 400,
          ),
          const DeviceLinkResize(cols: 92, rows: 30),
          const DeviceLinkDetach(),
          const DeviceLinkReclaimed(cols: 204, rows: 52),
          const DeviceLinkError(
            code: 'session_gone',
            message: 'Session is gone',
          ),
        ];

        for (final original in messages) {
          final decoded = DeviceLinkControlMessage.decode(original.encode());
          expect(decoded.type, original.type);
          expect(decoded.toJson(), equals(original.toJson()));
        }
      },
    );

    test('rejects malformed and unsupported control messages', () {
      expect(
        () => DeviceLinkControlMessage.decode('{not-json'),
        throwsA(isA<DeviceLinkProtocolException>()),
      );
      expect(
        () => DeviceLinkControlMessage.fromJson(const <String, Object?>{}),
        throwsA(isA<DeviceLinkProtocolException>()),
      );
      expect(
        () => DeviceLinkControlMessage.fromJson({
          't': 'hello',
          'v': deviceLinkProtocolVersion,
          'deviceId': 'phone-1',
        }),
        throwsA(isA<DeviceLinkProtocolException>()),
      );
      expect(
        () => DeviceLinkControlMessage.fromJson({
          't': 'hello',
          'v': deviceLinkProtocolVersion + 1,
          'deviceId': 'phone-1',
          'deviceName': 'Phone',
        }),
        throwsA(isA<DeviceLinkUnsupportedVersionException>()),
      );
      expect(
        () => DeviceLinkControlMessage.fromJson({
          't': 'unknown',
          'v': deviceLinkProtocolVersion,
        }),
        throwsA(isA<DeviceLinkProtocolException>()),
      );
      expect(
        () => DeviceLinkControlMessage.fromJson({
          't': 'resize',
          'v': deviceLinkProtocolVersion,
          'cols': '92',
          'rows': 30,
        }),
        throwsA(isA<DeviceLinkProtocolException>()),
      );
    });

    test('does not include secret fields in protocol errors', () {
      expect(
        () => DeviceLinkControlMessage.fromJson({
          't': 'hello',
          'v': deviceLinkProtocolVersion,
          'deviceId': 'phone-1',
          'secret': 'not-to-leak',
          'devicePublicKey': 'not-to-leak-either',
        }),
        throwsA(
          predicate<DeviceLinkProtocolException>(
            (error) =>
                !error.toString().contains('not-to-leak') &&
                !error.toString().contains('devicePublicKey'),
          ),
        ),
      );
    });
  });

  group('DeviceLinkBinaryFrame', () {
    test('round-trips raw payloads with their type prefix', () {
      const bytes = [0x00, 0xFF, 0x01, 0x02];
      final frame = DeviceLinkBinaryFrame(
        type: DeviceLinkBinaryFrameType.ptyOutput,
        payload: bytes,
      );

      final encoded = frame.encode();
      final decoded = DeviceLinkBinaryFrame.decode(encoded);

      expect(encoded, orderedEquals([0x01, ...bytes]));
      expect(decoded.type, DeviceLinkBinaryFrameType.ptyOutput);
      expect(decoded.payload, orderedEquals(bytes));
    });

    test('supports all defined frame types and empty payloads', () {
      for (final type in DeviceLinkBinaryFrameType.values) {
        final decoded = DeviceLinkBinaryFrame.decode(
          DeviceLinkBinaryFrame(type: type, payload: const []).encode(),
        );
        expect(decoded.type, type);
        expect(decoded.payload, isEmpty);
      }
    });

    test('rejects empty and unknown binary frames', () {
      expect(
        () => DeviceLinkBinaryFrame.decode(const <int>[]),
        throwsA(isA<DeviceLinkProtocolException>()),
      );
      expect(
        () => DeviceLinkBinaryFrame.decode(const [0x7F, 0x00]),
        throwsA(isA<DeviceLinkProtocolException>()),
      );
    });
  });

  test('control encoding is valid JSON text', () {
    const hello = DeviceLinkHello(deviceId: 'phone-1', deviceName: 'Phone');
    expect(jsonDecode(hello.encode()), isA<Map<String, dynamic>>());
  });
}
