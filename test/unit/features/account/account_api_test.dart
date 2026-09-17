import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_client.dart';
import 'package:shellvibe/features/account/data/account_api.dart';
import 'package:shellvibe/features/account/data/device_descriptor.dart';
import 'package:shellvibe/features/account/domain/account_session.dart';

import '../../../support/contract_fixture.dart';
import '../../../support/fake_api_transport.dart';

void main() {
  late FakeApiTransport transport;
  late AccountApi api;

  const descriptor = DeviceDescriptor(
    name: 'Fixture MacBook',
    platform: 'macos',
    appVersion: '2.0.0',
  );

  setUp(() {
    transport = FakeApiTransport();
    api = AccountApi(
      client: ApiClient(
        transport: transport,
        tokenProvider: () async => 'test-token',
      ),
    );
  });

  group('register', () {
    test('decodes the pinned auth.register fixture', () async {
      final fixture = ContractFixture.load('auth.register');
      transport.enqueue(status: fixture.status, body: fixture.body);

      final result = await api.register(
        name: 'Contract Fixture',
        email: 'contract@shellvibe.app',
        password: 'SecurePassword123!',
        device: descriptor,
      );

      expect(result.token, isNotEmpty);
      expect(result.session.userId, isNotEmpty);
      expect(result.session.deviceId, isNotEmpty);
      expect(result.session.email, 'contract@shellvibe.app');
      expect(result.session.name, 'Contract Fixture');
    });

    test('describes this device to the server', () async {
      final fixture = ContractFixture.load('auth.register');
      transport.enqueue(status: fixture.status, body: fixture.body);

      await api.register(
        name: 'A',
        email: 'a@b.c',
        password: 'x',
        device: descriptor,
      );

      expect(transport.lastBody['device_name'], 'Fixture MacBook');
      expect(transport.lastBody['platform'], 'macos');
      expect(transport.lastBody['app_version'], '2.0.0');
    });

    test('registers without a bearer token', () async {
      final fixture = ContractFixture.load('auth.register');
      transport.enqueue(status: fixture.status, body: fixture.body);

      await api.register(
        name: 'A',
        email: 'a@b.c',
        password: 'x',
        device: descriptor,
      );

      expect(
        transport.lastRequest!.headers.containsKey('Authorization'),
        isFalse,
      );
    });
  });

  group('login', () {
    test('decodes the pinned auth.login fixture', () async {
      final fixture = ContractFixture.load('auth.login');
      transport.enqueue(status: fixture.status, body: fixture.body);

      final result = await api.login(
        email: 'contract@shellvibe.app',
        password: 'SecurePassword123!',
        device: descriptor,
      );

      expect(result.token, isNotEmpty);
      expect(result.session.deviceId, isNotEmpty);
    });

    test('sends the known device id so the server reuses the record', () async {
      final fixture = ContractFixture.load('auth.login');
      transport.enqueue(status: fixture.status, body: fixture.body);

      await api.login(
        email: 'a@b.c',
        password: 'x',
        knownDeviceId: '01HZY7Q2K3M4N5P6R7S8T9V0WX',
        device: descriptor,
      );

      expect(transport.lastBody['device_id'], '01HZY7Q2K3M4N5P6R7S8T9V0WX');
    });

    test('omits device_id entirely on a first sign-in', () async {
      final fixture = ContractFixture.load('auth.login');
      transport.enqueue(status: fixture.status, body: fixture.body);

      await api.login(email: 'a@b.c', password: 'x', device: descriptor);

      expect(
        transport.lastBody.containsKey('device_id'),
        isFalse,
        reason: 'An empty device_id would fail validation, not be ignored.',
      );
    });

    test('never puts the password anywhere but the request body', () async {
      final fixture = ContractFixture.load('auth.login');
      transport.enqueue(status: fixture.status, body: fixture.body);

      await api.login(
        email: 'a@b.c',
        password: 'hunter2-should-not-leak',
        device: descriptor,
      );

      final request = transport.lastRequest!;
      expect(request.url.toString(), isNot(contains('hunter2')));
      expect(
        request.headers.values.join(' '),
        isNot(contains('hunter2')),
      );
    });
  });

  group('me and devices', () {
    test('decodes the pinned me fixture', () async {
      final fixture = ContractFixture.load('me');
      transport.enqueue(status: fixture.status, body: fixture.body);

      final session = await api.me();

      expect(session.userId, isNotEmpty);
      expect(session.deviceId, isNotEmpty);
      expect(session.email, 'contract@shellvibe.app');
    });

    test('decodes the pinned devices.index fixture', () async {
      final fixture = ContractFixture.load('devices.index');
      transport.enqueue(status: fixture.status, body: fixture.body);

      final devices = await api.devices();

      expect(devices, isNotEmpty);
      expect(devices.first.id, isNotEmpty);
      expect(devices.first.platform, isNotEmpty);
      expect(devices.first.isRevoked, isFalse);
    });

    test('tolerates a device DTO missing every optional field', () {
      // The contract permits backward-compatible additions, and a client that
      // throws on an absent optional field turns a cosmetic server change into
      // a broken device list.
      final device = AccountDeviceHarness.parse({'id': '01ABC'});

      expect(device.id, '01ABC');
      expect(device.name, 'Unknown device');
      expect(device.platform, 'unknown');
      expect(device.appVersion, isNull);
      expect(device.lastSeenAt, isNull);
      expect(device.isRevoked, isFalse);
    });

    test('reads revoked_at as a revocation', () {
      final device = AccountDeviceHarness.parse({
        'id': '01ABC',
        'revoked_at': '2026-09-17T10:00:00Z',
      });

      expect(device.isRevoked, isTrue);
      expect(device.revokedAt, isNotNull);
    });

    test('an unknown platform value survives decoding', () {
      // The contract says new enum values may appear and the client must be
      // fail-safe about them.
      final device = AccountDeviceHarness.parse({
        'id': '01ABC',
        'platform': 'some_future_platform',
      });

      expect(device.platform, 'some_future_platform');
    });
  });

  group('malformed success bodies', () {
    test('a token-less success is rejected rather than stored', () async {
      transport.enqueue(
        status: 201,
        body: {
          'data': {
            'user': {'id': '01U', 'email': 'a@b.c', 'name': 'A'},
            'device': {'id': '01D'},
          },
        },
      );

      await expectLater(
        api.register(
          name: 'A',
          email: 'a@b.c',
          password: 'x',
          device: descriptor,
        ),
        throwsA(isA<AccountApiException>()),
      );
    });

    test('a success without identifiers is rejected', () async {
      transport.enqueue(
        status: 201,
        body: {
          'data': {
            'token': 'abc',
            'user': {'email': 'a@b.c'},
            'device': {'name': 'x'},
          },
        },
      );

      await expectLater(
        api.register(
          name: 'A',
          email: 'a@b.c',
          password: 'x',
          device: descriptor,
        ),
        throwsA(isA<AccountApiException>()),
      );
    });
  });

  group('DeviceDescriptor', () {
    test('reports a platform the server accepts', () {
      const accepted = {'ios', 'android', 'macos', 'windows', 'linux', 'web'};

      expect(accepted, contains(DeviceDescriptor.currentPlatform()));
    });

    test('names the device without a .local suffix', () {
      final current = DeviceDescriptor.current();

      expect(current.name, isNotEmpty);
      expect(current.name.endsWith('.local'), isFalse);
      expect(current.appVersion, isNotEmpty);
    });
  });
}

/// Exposes [AccountDevice.fromJson] under a name that says it is a test seam.
abstract final class AccountDeviceHarness {
  static AccountDevice parse(Map<String, Object?> json) =>
      AccountDevice.fromJson(json);
}
