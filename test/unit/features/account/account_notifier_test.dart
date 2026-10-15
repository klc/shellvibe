import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_exception.dart';
import 'package:shellvibe/features/account/presentation/notifiers/account_notifier.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

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
}
