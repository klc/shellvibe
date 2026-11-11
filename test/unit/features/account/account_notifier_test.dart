import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_exception.dart';
import 'package:shellvibe/core/api/api_transport.dart';
import 'package:shellvibe/features/account/presentation/notifiers/account_notifier.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

import '../../../support/contract_fixture.dart';
import '../../../support/fake_api_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeApiTransport transport;
  late ProviderContainer container;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      SecureStorageKeys.accountToken: 'test-token',
      SecureStorageKeys.accountUserId: '01USERULID0000000000000000',
      SecureStorageKeys.accountDeviceId: '01DEVICEULID00000000000000',
      SecureStorageKeys.accountEmail: 'user@shellvibe.dev',
    });
    transport = FakeApiTransport();
    container = ProviderContainer(
      overrides: [accountApiTransportProvider.overrideWithValue(transport)],
    );
    addTearDown(container.dispose);
  });

  Future<String?> stored(String key) =>
      const FlutterSecureStorage().read(key: key);

  group('deleteAccount', () {
    test('a refusal changes nothing local, and a retry still runs', () async {
      expect((await container.read(accountProvider.future)).isSignedIn, isTrue);
      final notifier = container.read(accountProvider.notifier);

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
          body: {
            'data': {'deleted': true},
          },
        );

      await expectLater(
        notifier.deleteAccount(password: 'wrong'),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(accountProvider).value!.isSignedIn, isTrue);
      expect(await stored(SecureStorageKeys.accountToken), 'test-token');

      // The first failure must not stick in the queue and come back here
      // without a second request being made.
      await notifier.deleteAccount(password: 'right');

      expect(transport.sent, hasLength(2));
      expect(transport.lastBody, {'password': 'right'});
      expect(
        container.read(accountProvider).value!.status,
        AccountStatus.signedOut,
      );
      expect(await stored(SecureStorageKeys.accountToken), isNull);
      expect(await stored(SecureStorageKeys.accountUserId), isNull);
      expect(
        await stored(SecureStorageKeys.accountDeviceId),
        isNull,
        reason: 'The device record went with the account.',
      );
      expect(await stored(SecureStorageKeys.accountEmail), isNull);
    });

    test('no answer from the API keeps the session', () async {
      await container.read(accountProvider.future);
      transport.enqueueTransportFailure();

      await expectLater(
        container.read(accountProvider.notifier).deleteAccount(password: 'x'),
        throwsA(isA<ApiTransportException>()),
      );
      expect(container.read(accountProvider).value!.isSignedIn, isTrue);
      expect(await stored(SecureStorageKeys.accountToken), 'test-token');
    });
  });

  group('signOut', () {
    test(
      'everywhere keeps this session when the server is unreachable',
      () async {
        await container.read(accountProvider.future);
        transport.enqueueTransportFailure();

        await expectLater(
          container.read(accountProvider.notifier).signOut(everywhere: true),
          throwsA(isA<ApiTransportException>()),
        );

        expect(container.read(accountProvider).value!.isSignedIn, isTrue);
        expect(await stored(SecureStorageKeys.accountToken), 'test-token');
      },
    );

    test('everywhere signs out once the server confirms', () async {
      await container.read(accountProvider.future);
      transport.enqueue(status: 204);

      await container.read(accountProvider.notifier).signOut(everywhere: true);

      expect(transport.lastRequest!.url.path, endsWith('/auth/logout-all'));
      expect(
        container.read(accountProvider).value!.status,
        AccountStatus.signedOut,
      );
      expect(await stored(SecureStorageKeys.accountToken), isNull);
    });

    test('a 401 from logout leaves the account signed out', () async {
      await container.read(accountProvider.future);
      final fixture = ContractFixture.load('error.unauthenticated');
      transport.enqueue(status: fixture.status, body: fixture.body);

      await container.read(accountProvider.notifier).signOut();

      expect(
        container.read(accountProvider).value!.status,
        AccountStatus.signedOut,
      );
    });
  });

  test('a rebuild does not trip over its own fields', () async {
    await container.read(accountProvider.future);

    container.invalidate(accountProvider);

    expect((await container.read(accountProvider.future)).isSignedIn, isTrue);
  });

  test('a late 401 for an old token keeps the new session', () async {
    final gated = _GatedTransport(transport);
    final gatedContainer = ProviderContainer(
      overrides: [accountApiTransportProvider.overrideWithValue(gated)],
    );
    addTearDown(gatedContainer.dispose);
    await gatedContainer.read(accountProvider.future);
    final notifier = gatedContainer.read(accountProvider.notifier);

    // Sent with the old token, answered only after a fresh sign-in.
    final devices = notifier.devices();
    await gated.held.future;
    final login = ContractFixture.load('auth.login');
    transport.enqueue(status: login.status, body: login.body);
    await notifier.signIn(email: 'user@shellvibe.dev', password: 'pw');
    final newToken = await stored(SecureStorageKeys.accountToken);
    expect(newToken, isNot('test-token'));

    final unauthenticated = ContractFixture.load('error.unauthenticated');
    transport.enqueue(
      status: unauthenticated.status,
      body: unauthenticated.body,
    );
    gated.release.complete();
    await expectLater(devices, throwsA(isA<ApiException>()));
    await pumpEventQueue();

    expect(gatedContainer.read(accountProvider).value!.isSignedIn, isTrue);
    expect(await stored(SecureStorageKeys.accountToken), newToken);
  });
}

/// Holds the first request until [release] completes.
final class _GatedTransport implements ApiTransport {
  final FakeApiTransport inner;
  final Completer<void> held = Completer<void>();
  final Completer<void> release = Completer<void>();

  _GatedTransport(this.inner);

  @override
  Future<ApiRawResponse> send(ApiRawRequest request) async {
    if (!held.isCompleted) {
      held.complete();
      await release.future;
    }
    return inner.send(request);
  }

  @override
  void close() {}
}
