import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/crypto/encryption_engine.dart';
import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/identities_dao.dart';
import '../../../../shared/storage/secure_storage_service.dart';
import '../../domain/models/identity_model.dart';

class VaultRepository {
  final IdentitiesDao identitiesDao;
  final EncryptionEngine encryptionEngine;
  final SecureStorageService secureStorageService;

  VaultRepository({
    required this.identitiesDao,
    required this.encryptionEngine,
    required this.secureStorageService,
  });

  Future<SecretKey> _getOrCreateSecretKey() async {
    final keyBytes = await secureStorageService.getMasterKey();
    if (keyBytes != null) {
      return SecretKey(keyBytes);
    }
    // Generate 32-byte secret key and persist in secure storage
    final newSalt = encryptionEngine.generateSalt(32);
    await secureStorageService.saveMasterKey(newSalt);
    return SecretKey(newSalt);
  }

  Future<IdentityModel> saveIdentity({
    String? id,
    required String workspaceId,
    required String title,
    required String username,
    required String authType,
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    final secretKey = await _getOrCreateSecretKey();

    String? encPassword;
    String? encKey;
    String? encPassphrase;

    if (password != null && password.isNotEmpty) {
      encPassword = await encryptionEngine.encrypt(plaintext: password, secretKey: secretKey);
    }
    if (privateKey != null && privateKey.isNotEmpty) {
      encKey = await encryptionEngine.encrypt(plaintext: privateKey, secretKey: secretKey);
    }
    if (passphrase != null && passphrase.isNotEmpty) {
      encPassphrase = await encryptionEngine.encrypt(plaintext: passphrase, secretKey: secretKey);
    }

    final identityId = id ?? const Uuid().v4();
    final now = DateTime.now();

    final companion = IdentitiesCompanion(
      id: Value(identityId),
      workspaceId: Value(workspaceId),
      title: Value(title),
      username: Value(username),
      authType: Value(authType),
      passwordEncrypted: Value(encPassword),
      privateKeyEncrypted: Value(encKey),
      passphraseEncrypted: Value(encPassphrase),
      createdAt: Value(now),
    );

    if (id == null) {
      await identitiesDao.insertIdentity(companion);
    } else {
      await identitiesDao.updateIdentity(companion);
    }

    return IdentityModel(
      id: identityId,
      workspaceId: workspaceId,
      title: title,
      username: username,
      authType: authType,
      password: password,
      privateKey: privateKey,
      passphrase: passphrase,
      createdAt: now,
    );
  }

  Future<List<IdentityModel>> getAllIdentities({bool decryptSecrets = false}) async {
    final rows = await identitiesDao.getAllIdentities();
    final result = <IdentityModel>[];

    SecretKey? secretKey;
    if (decryptSecrets) {
      secretKey = await _getOrCreateSecretKey();
    }

    for (final row in rows) {
      String? password;
      String? privateKey;
      String? passphrase;

      if (decryptSecrets && secretKey != null) {
        if (row.passwordEncrypted != null) {
          try {
            password = await encryptionEngine.decrypt(
                encryptedBase64: row.passwordEncrypted!, secretKey: secretKey);
          } catch (_) {}
        }
        if (row.privateKeyEncrypted != null) {
          try {
            privateKey = await encryptionEngine.decrypt(
                encryptedBase64: row.privateKeyEncrypted!, secretKey: secretKey);
          } catch (_) {}
        }
        if (row.passphraseEncrypted != null) {
          try {
            passphrase = await encryptionEngine.decrypt(
                encryptedBase64: row.passphraseEncrypted!, secretKey: secretKey);
          } catch (_) {}
        }
      }

      result.add(
        IdentityModel(
          id: row.id,
          workspaceId: row.workspaceId,
          title: row.title,
          username: row.username,
          authType: row.authType,
          password: password,
          privateKey: privateKey,
          passphrase: passphrase,
          createdAt: row.createdAt,
        ),
      );
    }
    return result;
  }

  Future<IdentityModel?> getIdentityById(String id, {bool decryptSecrets = true}) async {
    final row = await identitiesDao.getIdentityById(id);
    if (row == null) return null;

    String? password;
    String? privateKey;
    String? passphrase;

    if (decryptSecrets) {
      final secretKey = await _getOrCreateSecretKey();
      if (row.passwordEncrypted != null) {
        try {
          password = await encryptionEngine.decrypt(
              encryptedBase64: row.passwordEncrypted!, secretKey: secretKey);
        } catch (_) {}
      }
      if (row.privateKeyEncrypted != null) {
        try {
          privateKey = await encryptionEngine.decrypt(
              encryptedBase64: row.privateKeyEncrypted!, secretKey: secretKey);
        } catch (_) {}
      }
      if (row.passphraseEncrypted != null) {
        try {
          passphrase = await encryptionEngine.decrypt(
              encryptedBase64: row.passphraseEncrypted!, secretKey: secretKey);
        } catch (_) {}
      }
    }

    return IdentityModel(
      id: row.id,
      workspaceId: row.workspaceId,
      title: row.title,
      username: row.username,
      authType: row.authType,
      password: password,
      privateKey: privateKey,
      passphrase: passphrase,
      createdAt: row.createdAt,
    );
  }

  Future<void> deleteIdentity(String id) async {
    await identitiesDao.deleteIdentity(id);
  }

  Stream<List<Identity>> watchIdentities() {
    return identitiesDao.watchAllIdentities();
  }
}
