import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/features/cloud_backup/data/cloud_backup_store.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// A [CloudBackupStore] over the mock keychain, sealing under the vault key
/// the app itself would use there: with no master password, the one in the
/// keychain.
CloudBackupStore testCloudBackupStore() => CloudBackupStore(
  storage: SecureStorageService(),
  vaultKey: VaultKeyService(
    encryptionEngine: EncryptionEngine(),
    secureStorageService: SecureStorageService(),
  ).getDek,
);
