import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/cloud_backup/data/cloud_backup_store.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// Where the sync key comes from, and why it cannot come from anywhere else.
///
/// Every device has to hold the *same* key, and it cannot be derived from the
/// passphrase -- changing the passphrase would then make the whole operation
/// log unreadable. So one device mints it, seals it into a backup, and the
/// others learn it by opening that backup. Nothing about that is visible when
/// it goes wrong: two devices with different keys simply skip each other's
/// operations and sync looks like it is running while carrying nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CloudBackupStore store;

  Uint8List fixedKey(int seed) =>
      Uint8List.fromList(List<int>.filled(32, seed));

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    store = CloudBackupStore(storage: SecureStorageService());
  });

  group('minting', () {
    test('no key is sealed while automatic sync is off', () async {
      // Which keeps the envelope at v3 and readable by builds that predate
      // v4. There is no reason to spend that on a feature nobody asked for.
      final key = await store.syncKeyForUpload(autoSyncEnabled: false);

      expect(key, isNull);
      expect(await store.readSyncKey(), isNull);
    });

    test('switching sync on mints a key with the next backup', () async {
      final key = await store.syncKeyForUpload(autoSyncEnabled: true);

      expect(key, isNotNull);
      expect(key, hasLength(32));
      expect(await store.readSyncKey(), base64.encode(key!));
    });

    test('the key is minted once and then reused', () async {
      // A second key would make everything written under the first
      // unreadable, on this device and every other one.
      final first = await store.syncKeyForUpload(autoSyncEnabled: true);
      final second = await store.syncKeyForUpload(autoSyncEnabled: true);

      expect(second, first);
    });

    test('a known key is sealed even when sync is switched off', () async {
      // Turning sync off does not mean other devices should stop being able
      // to read what this one backs up.
      await store.writeSyncKey(base64.encode(fixedKey(7)));

      expect(await store.syncKeyForUpload(autoSyncEnabled: false), fixedKey(7));
    });
  });

  group('adopting', () {
    test('a backup that carries a key hands it over', () async {
      await store.adoptSyncKey(SecretKey(fixedKey(3)));

      expect(await store.readSyncKey(), base64.encode(fixedKey(3)));
    });

    test('a backup without one changes nothing', () async {
      // Every v3 envelope, and every v4 written before sync was switched on.
      await store.adoptSyncKey(null);

      expect(await store.readSyncKey(), isNull);
    });

    test('a key already held is never replaced', () async {
      // The failure this prevents is silent: two devices each minting a key
      // would seal their own into their own backups and skip each other's
      // operations, with sync reporting success the whole time.
      await store.writeSyncKey(base64.encode(fixedKey(1)));

      await store.adoptSyncKey(SecretKey(fixedKey(2)));

      expect(await store.readSyncKey(), base64.encode(fixedKey(1)));
    });

    test('a device that adopts does not mint its own', () async {
      await store.adoptSyncKey(SecretKey(fixedKey(9)));

      expect(await store.syncKeyForUpload(autoSyncEnabled: true), fixedKey(9));
    });
  });

  group('the ground overrules', () {
    test('a key minted before the ground existed is replaced', () async {
      // The split this closes: two devices switch sync on at the same time,
      // each mints a key, and from then on each pushes a log the other
      // silently discards. The ground is what every joining device starts
      // from, so the key it carries is the account's by definition.
      await store.writeSyncKey(base64.encode(fixedKey(1)));

      final replaced = await store.adoptGroundSyncKey(SecretKey(fixedKey(2)));

      expect(replaced, isTrue);
      expect(await store.readSyncKey(), base64.encode(fixedKey(2)));
    });

    test('the same key is not a change', () async {
      // The ordinary case, on every start. Reporting a change here would send
      // the device off to rewrite the ground for nothing.
      await store.writeSyncKey(base64.encode(fixedKey(3)));

      expect(await store.adoptGroundSyncKey(SecretKey(fixedKey(3))), isFalse);
    });

    test('a ground with no key changes nothing', () async {
      await store.writeSyncKey(base64.encode(fixedKey(4)));

      expect(await store.adoptGroundSyncKey(null), isFalse);
      expect(await store.readSyncKey(), base64.encode(fixedKey(4)));
    });

    test('a device with no key of its own takes the ground\'s', () async {
      expect(await store.adoptGroundSyncKey(SecretKey(fixedKey(6))), isTrue);
      expect(await store.readSyncKey(), base64.encode(fixedKey(6)));
    });
  });

  test('forgetting this device forgets the key too', () async {
    // A key left behind would be offered against the next account's vault,
    // which it cannot open.
    await store.writePassphrase('passphrase');
    await store.writeSyncKey(base64.encode(fixedKey(5)));

    await store.clear();

    expect(await store.readSyncKey(), isNull);
  });
}
