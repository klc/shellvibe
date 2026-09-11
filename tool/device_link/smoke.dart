// Faz 1 loopback smoke test for the Device Link TLS/WebSocket transport.
//
//   dart run tool/device_link/smoke.dart
//
// It binds only to 127.0.0.1 and does not require Docker or a physical device.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellvibe/core/network/device_link/device_link_client.dart';
import 'package:shellvibe/core/network/device_link/device_link_identity.dart';
import 'package:shellvibe/core/network/device_link/device_link_protocol.dart';
import 'package:shellvibe/core/network/device_link/device_link_server.dart';

const _timeout = Duration(seconds: 10);

Future<void> main() async {
  final checks = _Checks();
  final identity = DeviceLinkIdentity.generate();
  final server = DeviceLinkServer(
    identity: identity,
    hostName: 'loopback-host',
    appVersion: 'smoke',
  );
  DeviceLinkClientConnection? connection;

  try {
    await server.start();
    final payload = await server.createPairingPayload(
      addresses: const ['127.0.0.1'],
    );
    stdout.writeln('→ TLS server 127.0.0.1:${server.port}');

    final client = DeviceLinkClient(connectionTimeout: _timeout);
    connection = await client.connectToQrPayload(payload).timeout(_timeout);
    checks.expect('correct SPKI pin connects', !connection.isClosed);

    await connection.sendHello(
      const DeviceLinkHello(deviceId: 'smoke-device', deviceName: 'Smoke'),
    );
    final helloAck = await connection.nextControl(timeout: _timeout);
    checks.expect('hello/hello_ack succeeds', helloAck is DeviceLinkHelloAck);

    await connection.sendPair(
      DeviceLinkPair(
        token: 'wrong-token',
        deviceName: 'Smoke',
        devicePublicKey: 'smoke-public-key',
      ),
    );
    final wrongToken = await connection.nextControl(timeout: _timeout);
    checks.expect(
      'wrong pairing token is rejected',
      _isErrorCode(wrongToken, 'pairing_token_invalid'),
    );

    await connection.sendPair(
      DeviceLinkPair(
        token: payload.token,
        deviceName: 'Smoke',
        devicePublicKey: 'smoke-public-key',
      ),
    );
    final paired = await connection.nextControl(timeout: _timeout);
    checks.expect('pair/paired succeeds', paired is DeviceLinkPaired);
    final authenticatedHello = await connection.nextControl(timeout: _timeout);
    checks.expect(
      'authenticated hello_ack follows pairing',
      authenticatedHello is DeviceLinkHelloAck,
    );

    await connection.sendPair(
      DeviceLinkPair(
        token: payload.token,
        deviceName: 'Smoke',
        devicePublicKey: 'smoke-public-key',
      ),
    );
    final secondUse = await connection.nextControl(timeout: _timeout);
    checks.expect(
      'second use of token is rejected',
      _isErrorCode(secondUse, 'pairing_token_invalid'),
    );

    await connection.sendRawText(
      jsonEncode({'t': 'hello', 'v': deviceLinkProtocolVersion + 1}),
    );
    final versionError = await connection.nextControl(timeout: _timeout);
    checks.expect(
      'protocol version mismatch is rejected',
      _isErrorCode(versionError, 'unsupported_version'),
    );
    await connection.close();
    connection = null;

    final wrongPinClient = DeviceLinkClient(connectionTimeout: _timeout);
    try {
      await wrongPinClient
          .connect([
            DeviceLinkEndpoint(
              host: '127.0.0.1',
              port: server.port,
              spkiSha256Base64: 'wrong-pin',
            ),
          ])
          .timeout(_timeout);
      checks.fail(
        'wrong SPKI pin is rejected',
        'connection unexpectedly succeeded',
      );
    } catch (_) {
      checks.expect('wrong SPKI pin is rejected', true);
    }

    final expiredPayload = await server.createPairingPayload(
      addresses: const ['127.0.0.1'],
      now: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
    );
    checks.expect(
      'expired token is rejected',
      !server.pairingTokens.consume(
        expiredPayload.token,
        now: DateTime.now().toUtc(),
      ),
    );
  } on TimeoutException catch (error) {
    checks.fail('smoke timed out', error.toString());
  } on DeviceLinkTransportException catch (error) {
    final cause = error.cause is DeviceLinkTransportException
        ? (error.cause! as DeviceLinkTransportException).cause
        : error.cause;
    checks.fail('transport error', '${error.code}: ${cause ?? error.message}');
  } catch (error, stack) {
    checks.fail('unexpected smoke error', '$error\n$stack');
  } finally {
    await connection?.close();
    await server.close();
  }

  stdout.writeln('');
  stdout.writeln(checks.summary);
  exitCode = checks.passed ? 0 : 1;
}

bool _isErrorCode(DeviceLinkControlMessage message, String code) =>
    message is DeviceLinkError && message.code == code;

class _Checks {
  final _failures = <String>[];
  var _total = 0;

  bool get passed => _failures.isEmpty;

  void expect(String name, bool condition, [String detail = '']) {
    _total++;
    if (condition) {
      stdout.writeln('  ✓ $name');
    } else {
      fail(name, detail, counted: true);
    }
  }

  void fail(String name, String detail, {bool counted = false}) {
    if (!counted) _total++;
    _failures.add(name);
    stdout.writeln('  ✗ $name${detail.isEmpty ? '' : ' — $detail'}');
  }

  String get summary => passed
      ? '$_total/$_total passed — Device Link loopback transport is healthy.'
      : '${_total - _failures.length}/$_total passed — failed: '
            '${_failures.join(', ')}';
}
