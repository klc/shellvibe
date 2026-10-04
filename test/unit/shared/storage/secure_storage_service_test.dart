import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final bundled in [false, true]) {
    group('SecureStorageService Unit Tests (bundled: $bundled)', () {
      late SecureStorageService storageService;

      setUp(() {
        FlutterSecureStorage.setMockInitialValues({});
        storageService = SecureStorageService(bundled: bundled);
      });

      test('Master Key save, get, and delete operations', () async {
        expect(await storageService.getMasterKey(), isNull);

        final testKeyBytes = Uint8List.fromList(
          List.generate(32, (i) => i + 1),
        );
        await storageService.saveMasterKey(testKeyBytes);

        final retrievedKey = await storageService.getMasterKey();
        expect(retrievedKey, isNotNull);
        expect(retrievedKey, equals(testKeyBytes));

        await storageService.deleteMasterKey();
        expect(await storageService.getMasterKey(), isNull);
      });

      test('Master Salt save, get, and delete operations', () async {
        expect(await storageService.getMasterSalt(), isNull);

        final testSaltBytes = Uint8List.fromList(
          List.generate(16, (i) => i * 2),
        );
        await storageService.saveMasterSalt(testSaltBytes);

        final retrievedSalt = await storageService.getMasterSalt();
        expect(retrievedSalt, isNotNull);
        expect(retrievedSalt, equals(testSaltBytes));

        await storageService.deleteMasterSalt();
        expect(await storageService.getMasterSalt(), isNull);
      });

      test('Token save, get, and delete operations', () async {
        final tokenKey = 'oauth_github';
        final tokenValue = 'ghp_secret_access_token_123456';

        expect(await storageService.getToken(tokenKey), isNull);

        await storageService.saveToken(tokenKey, tokenValue);
        expect(await storageService.getToken(tokenKey), equals(tokenValue));

        await storageService.deleteToken(tokenKey);
        expect(await storageService.getToken(tokenKey), isNull);
      });

      test('Generic key-value CRUD operations and deleteAll', () async {
        await storageService.write(key: 'key1', value: 'val1');
        await storageService.write(key: 'key2', value: 'val2');

        expect(await storageService.containsKey(key: 'key1'), isTrue);
        expect(await storageService.read(key: 'key1'), equals('val1'));

        await storageService.delete(key: 'key1');
        expect(await storageService.containsKey(key: 'key1'), isFalse);

        await storageService.deleteAll();
        expect(await storageService.containsKey(key: 'key2'), isFalse);
      });
    });
  }

  group('macOS single keychain item', () {
    const raw = FlutterSecureStorage();

    SecureStorageService bundled() => SecureStorageService(bundled: true);

    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('every secret lands in one item', () async {
      final storage = bundled();
      await storage.write(key: 'shellvibe_a', value: '1');
      await storage.write(key: 'shellvibe_b', value: '2');
      await storage.saveToken('github', 'tok');

      expect((await raw.readAll()).keys, [SecureStorageService.bundleKey]);

      final reopened = bundled();
      expect(await reopened.read(key: 'shellvibe_a'), '1');
      expect(await reopened.read(key: 'shellvibe_b'), '2');
      expect(await reopened.getToken('github'), 'tok');
    });

    test('an item from before the bundle moves in when first read', () async {
      FlutterSecureStorage.setMockInitialValues({
        SecureStorageKeys.masterKey: 'dek',
        SecureStorageKeys.accountToken: 'bearer',
      });

      final storage = bundled();
      expect(await storage.read(key: SecureStorageKeys.masterKey), 'dek');

      final left = await raw.readAll();
      expect(left.containsKey(SecureStorageKeys.masterKey), isFalse);
      expect(
        left.containsKey(SecureStorageKeys.accountToken),
        isTrue,
        reason: 'a key nobody asked for is left where it is',
      );

      expect(
        await bundled().read(key: SecureStorageKeys.masterKey),
        'dek',
        reason: 'the moved value survives a relaunch',
      );
      expect(
        await storage.containsKey(key: SecureStorageKeys.accountToken),
        isTrue,
      );
      expect((await raw.readAll()).keys, [SecureStorageService.bundleKey]);
    });

    test('overwriting or deleting drops the old item for good', () async {
      FlutterSecureStorage.setMockInitialValues({
        'shellvibe_overwritten': 'old',
        'shellvibe_deleted': 'old',
      });

      final storage = bundled();
      await storage.write(key: 'shellvibe_overwritten', value: 'new');
      await storage.delete(key: 'shellvibe_deleted');

      final reopened = bundled();
      expect(await reopened.read(key: 'shellvibe_overwritten'), 'new');
      expect(
        await reopened.read(key: 'shellvibe_deleted'),
        isNull,
        reason: 'the pre-bundle item must not come back after a delete',
      );
      expect((await raw.readAll()).keys, [SecureStorageService.bundleKey]);
    });

    test('the terly2 fallback still finds a renamed key', () async {
      FlutterSecureStorage.setMockInitialValues({'terly2_master_salt': 'salt'});

      expect(await bundled().read(key: SecureStorageKeys.masterSalt), 'salt');
      expect(await bundled().read(key: SecureStorageKeys.masterSalt), 'salt');
    });

    test('writes racing each other all survive', () async {
      final storage = bundled();
      await Future.wait([
        for (var i = 0; i < 20; i++)
          storage.write(key: 'shellvibe_k$i', value: '$i'),
      ]);

      final reopened = bundled();
      for (var i = 0; i < 20; i++) {
        expect(await reopened.read(key: 'shellvibe_k$i'), '$i');
      }
    });

    test('deleteAll takes the bundle and older items with it', () async {
      FlutterSecureStorage.setMockInitialValues({'shellvibe_old': 'x'});
      final storage = bundled();
      await storage.write(key: 'shellvibe_new', value: 'y');

      await storage.deleteAll();

      expect(await raw.readAll(), isEmpty);
      expect(await storage.read(key: 'shellvibe_new'), isNull);
      expect(await bundled().read(key: 'shellvibe_old'), isNull);
    });

    test('is off by default under flutter test', () async {
      await SecureStorageService().write(key: 'shellvibe_plain', value: 'v');

      expect((await raw.readAll()).keys, ['shellvibe_plain']);
    });
  });
}
