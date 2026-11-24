import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_client.dart';
import 'package:shellvibe/core/api/api_exception.dart';
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

  group('browser sign-in', () {
    test('decodes the pinned auth.app-sign-in.store fixture', () async {
      final fixture = ContractFixture.load('auth.app-sign-in.store');
      transport.enqueue(status: fixture.status, body: fixture.body);

      final request = await api.startBrowserSignIn(device: descriptor);

      expect(request.id, isNotEmpty);
      expect(request.secret, isNotEmpty);
      expect(request.userCode, isNotEmpty);
      expect(request.verificationUrl, isNotEmpty);
      expect(request.interval, const Duration(seconds: 2));
    });

    test('describes this device, unauthenticated', () async {
      final fixture = ContractFixture.load('auth.app-sign-in.store');
      transport.enqueue(status: fixture.status, body: fixture.body);

      await api.startBrowserSignIn(device: descriptor);

      expect(transport.lastBody['device_name'], 'Fixture MacBook');
      expect(transport.lastBody['platform'], 'macos');
      expect(transport.lastBody['app_version'], '2.0.0');
      expect(
        transport.lastRequest!.headers.containsKey('Authorization'),
        isFalse,
      );
    });

    test('sends the known device id so the server reuses the record', () async {
      final fixture = ContractFixture.load('auth.app-sign-in.store');
      transport.enqueue(status: fixture.status, body: fixture.body);

      await api.startBrowserSignIn(
        knownDeviceId: '01HZY7Q2K3M4N5P6R7S8T9V0WX',
        device: descriptor,
      );

      expect(transport.lastBody['device_id'], '01HZY7Q2K3M4N5P6R7S8T9V0WX');
    });

    test('omits device_id entirely on a first sign-in', () async {
      final fixture = ContractFixture.load('auth.app-sign-in.store');
      transport.enqueue(status: fixture.status, body: fixture.body);

      await api.startBrowserSignIn(device: descriptor);

      expect(
        transport.lastBody.containsKey('device_id'),
        isFalse,
        reason: 'An empty device_id would fail validation, not be ignored.',
      );
    });

    test('a pending poll is null; an approved one is the session', () async {
      final pending = ContractFixture.load('auth.app-sign-in.token.pending');
      final approved = ContractFixture.load('auth.app-sign-in.token');
      transport
        ..enqueue(status: pending.status, body: pending.body)
        ..enqueue(status: approved.status, body: approved.body);

      expect(await api.pollBrowserSignIn(_request), isNull);
      final result = await api.pollBrowserSignIn(_request);

      expect(result!.token, isNotEmpty);
      expect(result.session.userId, isNotEmpty);
      expect(result.session.deviceId, isNotEmpty);
      expect(result.session.email, 'contract@shellvibe.app');
    });

    test('polls with the secret in the body only', () async {
      final pending = ContractFixture.load('auth.app-sign-in.token.pending');
      transport.enqueue(status: pending.status, body: pending.body);

      await api.pollBrowserSignIn(_request);

      final request = transport.lastRequest!;
      expect(request.url.path, endsWith('/auth/app-sign-in/01REQ/token'));
      expect(transport.lastBody, {'secret': 'the-secret'});
      expect(request.url.toString(), isNot(contains('the-secret')));
      expect(request.headers.containsKey('Authorization'), isFalse);
    });

    test('a denial surfaces as sign_in_denied', () async {
      transport.enqueue(
        status: 403,
        body: {
          'code': 'sign_in_denied',
          'message': 'The sign-in was denied in the browser.',
          'details': <String, Object?>{},
        },
      );

      await expectLater(
        api.pollBrowserSignIn(_request),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.signInDenied,
          ),
        ),
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

  group('deleteAccount', () {
    test('sends the password in the body of an authenticated DELETE', () async {
      transport.enqueue(
        body: {
          'data': {'deleted': true, 'removed_without_cascade': <String, int>{}},
        },
      );

      await api.deleteAccount(password: 'hunter2-should-not-leak');

      final request = transport.lastRequest!;
      expect(request.method, 'DELETE');
      expect(request.url.path, endsWith('/api/v1/account'));
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(transport.lastBody, {'password': 'hunter2-should-not-leak'});
      expect(request.url.toString(), isNot(contains('hunter2')));
    });

    test('surfaces the server\'s refusals by code', () async {
      transport
        ..enqueue(
          status: 422,
          body: {
            'code': 'invalid_credentials',
            'message': 'The password does not match this account.',
            'details': <String, Object?>{},
          },
        )
        ..enqueue(
          status: 409,
          body: {
            'code': 'account_owns_shared_team',
            'message': 'Transfer or empty every team you own first.',
            'details': {
              'team_ids': ['01TEAM'],
            },
          },
        );

      await expectLater(
        api.deleteAccount(password: 'wrong'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.invalidCredentials,
          ),
        ),
      );
      await expectLater(
        api.deleteAccount(password: 'right'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.accountOwnsSharedTeam,
          ),
        ),
      );
    });
  });

  group('malformed success bodies', () {
    test('a token-less success is rejected rather than stored', () async {
      transport.enqueue(
        status: 201,
        body: {
          'data': {
            'status': 'approved',
            'user': {'id': '01U', 'email': 'a@b.c', 'name': 'A'},
            'device': {'id': '01D'},
          },
        },
      );

      await expectLater(
        api.pollBrowserSignIn(_request),
        throwsA(isA<AccountApiException>()),
      );
    });

    test('a success without identifiers is rejected', () async {
      transport.enqueue(
        status: 201,
        body: {
          'data': {
            'status': 'approved',
            'token': 'abc',
            'user': {'email': 'a@b.c'},
            'device': {'name': 'x'},
          },
        },
      );

      await expectLater(
        api.pollBrowserSignIn(_request),
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

const _request = BrowserSignIn(
  id: '01REQ',
  secret: 'the-secret',
  userCode: 'ABCD-EFGH',
  verificationUrl: 'https://shellvibe.dev/panel/app-sign-in/01REQ',
);

/// Exposes [AccountDevice.fromJson] under a name that says it is a test seam.
abstract final class AccountDeviceHarness {
  static AccountDevice parse(Map<String, Object?> json) =>
      AccountDevice.fromJson(json);
}
