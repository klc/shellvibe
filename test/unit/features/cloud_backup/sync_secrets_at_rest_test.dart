import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/e2ee_cloud_sync_service.dart';
import 'package:shellvibe/features/cloud_backup/data/cloud_backup_store.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

import '../../../support/fast_crypto.dart';

/// The passphrase, the recovery code and the sync key each open everything
/// this account uploads, and what it uploads carries the vault key. Kept in
/// the clear they would make a master password decorative: reading the
/// keychain would be enough after all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  const passphrase = 'dummy-cloud-passphrase';
  const recoveryCode = 'DUMMYRECOVERYCODE';
  // Built rather than written out: a literal key trips the secret scan.
  final syncKey = base64.encode(List<int>.filled(32, 7));

  VaultKeyService vaultKeys() => VaultKeyService(
    encryptionEngine: fastEncryptionEngine(),
    secureStorageService: SecureStorageService(),
  );

  CloudBackupStore storeOver(VaultKeyService keys) =>
      CloudBackupStore(storage: SecureStorageService(), vaultKey: keys.getDek);

  /// Every value in the keychain, as a reader of it would see them.
  Future<String> keychain() async =>
      (await const FlutterSecureStorage().readAll()).values.join('\n');

  Future<void> writeAll(CloudBackupStore store) async {
    await store.writePassphrase(passphrase);
    await store.writeRecoveryCode(recoveryCode);
    await store.writeSyncKey(syncKey);
  }

  test('none of the three is readable from the keychain', () async {
    final store = storeOver(vaultKeys());
    await writeAll(store);

    final raw = await keychain();
    expect(raw, isNot(contains(passphrase)));
    expect(raw, isNot(contains(recoveryCode)));
    expect(raw, isNot(contains(syncKey)));

    expect(await store.readPassphrase(), passphrase);
    expect(await store.readRecoveryCode(), recoveryCode);
    expect(await store.readSyncKey(), syncKey);
  });

  test('with the vault locked, a keychain reader gets neither the secrets nor '
      'the vault key through them', () async {
    final keys = vaultKeys();
    await keys.getDek();
    await keys.configureMasterPassword('dummy-master-password');
    await writeAll(storeOver(keys));

    // A backup sealed while unlocked, as the reader could fetch it.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await E2EECloudSyncService(
      vaultKeyService: keys,
      cryptoEngine: fastEncryptionEngine(),
    ).exportEncryptedBackup(db: db, masterPassword: passphrase);
    keys.lock();

    final reader = storeOver(vaultKeys());

    expect(await keychain(), isNot(contains(passphrase)));
    await expectLater(
      reader.readPassphrase(),
      throwsA(isA<VaultLockedException>()),
    );
    await expectLater(
      reader.readRecoveryCode(),
      throwsA(isA<VaultLockedException>()),
    );
    await expectLater(
      reader.readSyncKey(),
      throwsA(isA<VaultLockedException>()),
    );

    // What a locked screen still needs to know.
    expect(await reader.isConfigured(), isTrue);
    expect(await reader.hasRecoveryCode(), isTrue);
  });

  test('a value an earlier build left in the clear is moved on read', () async {
    final storage = SecureStorageService();
    await storage.write(key: 'shellvibe_sync_passphrase', value: passphrase);

    final store = storeOver(vaultKeys());

    expect(await store.readPassphrase(), passphrase);
    expect(await storage.read(key: 'shellvibe_sync_passphrase'), isNull);
    expect(await keychain(), isNot(contains(passphrase)));
    expect(await store.readPassphrase(), passphrase);
  });

  test('a value left in the clear is still readable behind a lock', () async {
    // Refusing it would stop backup on every device that has one; it moves
    // under the vault key on the first read with the vault open.
    final keys = vaultKeys();
    await keys.getDek();
    await keys.configureMasterPassword('dummy-master-password');
    keys.lock();

    final storage = SecureStorageService();
    await storage.write(key: 'shellvibe_sync_passphrase', value: passphrase);

    final store = storeOver(keys);

    expect(await store.readPassphrase(), passphrase);
    expect(await storage.read(key: 'shellvibe_sync_passphrase'), passphrase);

    await keys.unlock('dummy-master-password');
    expect(await store.readPassphrase(), passphrase);
    expect(await storage.read(key: 'shellvibe_sync_passphrase'), isNull);
  });

  test('forgetting the device forgets the sealed copies too', () async {
    final store = storeOver(vaultKeys());
    await writeAll(store);

    await store.clear();

    expect(await store.isConfigured(), isFalse);
    expect(await store.hasRecoveryCode(), isFalse);
    expect(await store.readSyncKey(), isNull);
  });
}
