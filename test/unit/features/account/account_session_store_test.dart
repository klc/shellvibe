import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/account/data/account_session_store.dart';
import 'package:shellvibe/features/account/domain/account_session.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccountSessionStore store;

  const session = AccountSession(
    userId: '01USERULID0000000000000000',
    deviceId: '01DEVICEULID00000000000000',
    email: 'user@shellvibe.dev',
    name: 'User',
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    store = AccountSessionStore(storage: SecureStorageService());
  });

  test('reads nothing when signed out', () async {
    expect(await store.readToken(), isNull);
    expect(await store.read(), isNull);
  });

  test('round-trips a written session', () async {
    await store.write(token: 'tok_123', session: session);

    expect(await store.readToken(), 'tok_123');

    final restored = await store.read();
    expect(restored, isNotNull);
    expect(restored!.userId, session.userId);
    expect(restored.deviceId, session.deviceId);
    expect(restored.email, session.email);
  });

  test('clearSession keeps the device id so the next sign-in reuses it', () async {
    await store.write(token: 'tok_123', session: session);
    await store.clearSession();

    expect(await store.readToken(), isNull);
    expect(await store.read(), isNull);
    expect(
      await store.readDeviceId(),
      session.deviceId,
      reason:
          'Forgetting the device id makes the server open a second device '
          'record for this machine on the next sign-in.',
    );
  });

  test('clearSession keeps the email for prefilling the form', () async {
    await store.write(token: 'tok_123', session: session);
    await store.clearSession();

    expect(await store.readEmail(), session.email);
  });

  test('clearAll forgets the device identity too', () async {
    await store.write(token: 'tok_123', session: session);
    await store.clearAll();

    expect(await store.readToken(), isNull);
    expect(await store.readDeviceId(), isNull);
    expect(await store.readEmail(), isNull);
  });

  test('a token without a user id is not a session', () async {
    // Half-written state, e.g. the process died between two keychain writes.
    FlutterSecureStorage.setMockInitialValues({
      SecureStorageKeys.accountToken: 'tok_123',
    });
    store = AccountSessionStore(storage: SecureStorageService());

    expect(await store.readToken(), 'tok_123');
    expect(
      await store.read(),
      isNull,
      reason: 'An incomplete session must not be published as signed in.',
    );
  });

  test('an empty stored token reads as signed out', () async {
    FlutterSecureStorage.setMockInitialValues({
      SecureStorageKeys.accountToken: '',
      SecureStorageKeys.accountUserId: session.userId,
      SecureStorageKeys.accountDeviceId: session.deviceId,
    });
    store = AccountSessionStore(storage: SecureStorageService());

    expect(await store.readToken(), isNull);
    expect(await store.read(), isNull);
  });

  test('the token is stored under its own key, not the vault keys', () async {
    await store.write(token: 'tok_123', session: session);

    expect(SecureStorageKeys.accountToken, isNot(SecureStorageKeys.masterKey));
    expect(
      SecureStorageKeys.accountToken,
      isNot(SecureStorageKeys.wrappedDek),
    );
    expect(await store.readToken(), 'tok_123');
  });
}
