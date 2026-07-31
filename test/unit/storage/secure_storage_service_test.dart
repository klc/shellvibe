import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/shared/storage/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureStorageService Unit Tests', () {
    late SecureStorageService storageService;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      storageService = SecureStorageService();
    });

    test('Master Key save, get, and delete operations', () async {
      expect(await storageService.getMasterKey(), isNull);

      final testKeyBytes = Uint8List.fromList(List.generate(32, (i) => i + 1));
      await storageService.saveMasterKey(testKeyBytes);

      final retrievedKey = await storageService.getMasterKey();
      expect(retrievedKey, isNotNull);
      expect(retrievedKey, equals(testKeyBytes));

      await storageService.deleteMasterKey();
      expect(await storageService.getMasterKey(), isNull);
    });

    test('Master Salt save, get, and delete operations', () async {
      expect(await storageService.getMasterSalt(), isNull);

      final testSaltBytes = Uint8List.fromList(List.generate(16, (i) => i * 2));
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
