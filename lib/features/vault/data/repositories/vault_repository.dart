import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/crypto/encryption_engine.dart';
import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/identities_dao.dart';
import '../../domain/models/identity_model.dart';
import '../vault_key_service.dart';

/// Thrown when a stored secret cannot be decrypted with the current vault key.
class SecretDecryptionException implements Exception {
  final String identityId;
  final String field;

  const SecretDecryptionException(this.identityId, this.field);

  @override
  String toString() =>
      'SecretDecryptionException: cannot decrypt "$field" of identity '
      '$identityId. It was encrypted with a different vault key.';
}

class VaultRepository {
  final IdentitiesDao identitiesDao;
  final EncryptionEngine encryptionEngine;
  final VaultKeyService vaultKeyService;

  VaultRepository({
    required this.identitiesDao,
    required this.encryptionEngine,
    required this.vaultKeyService,
  });

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
    final secretKey = await vaultKeyService.getDek();

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

  /// Lists identities. With [decryptSecrets] the secrets are decrypted
  /// best-effort: a row whose secrets are unreadable is still returned, flagged
  /// with [IdentityModel.hasUndecryptableSecrets] instead of silently blank.
  Future<List<IdentityModel>> getAllIdentities({bool decryptSecrets = false}) async {
    final rows = await identitiesDao.getAllIdentities();
    final result = <IdentityModel>[];

    // Never touch the key service when secrets are not requested, so listing
    // identities keeps working while a protected vault is locked.
    SecretKey? secretKey;
    if (decryptSecrets) {
      secretKey = await vaultKeyService.getDek();
    }

    for (final row in rows) {
      String? password;
      String? privateKey;
      String? passphrase;
      var undecryptable = false;

      if (decryptSecrets && secretKey != null) {
        try {
          password = await _decryptField(row.passwordEncrypted, secretKey, row.id, 'password');
          privateKey =
              await _decryptField(row.privateKeyEncrypted, secretKey, row.id, 'privateKey');
          passphrase =
              await _decryptField(row.passphraseEncrypted, secretKey, row.id, 'passphrase');
        } on SecretDecryptionException {
          undecryptable = true;
          password = null;
          privateKey = null;
          passphrase = null;
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
          hasUndecryptableSecrets: undecryptable,
        ),
      );
    }
    return result;
  }

  /// Loads a single identity.
  ///
  /// Throws [SecretDecryptionException] when [decryptSecrets] is set and a
  /// stored secret cannot be decrypted — callers must surface this rather than
  /// connecting with silently missing credentials.
  Future<IdentityModel?> getIdentityById(String id, {bool decryptSecrets = true}) async {
    final row = await identitiesDao.getIdentityById(id);
    if (row == null) return null;

    String? password;
    String? privateKey;
    String? passphrase;

    if (decryptSecrets) {
      final secretKey = await vaultKeyService.getDek();
      password = await _decryptField(row.passwordEncrypted, secretKey, row.id, 'password');
      privateKey = await _decryptField(row.privateKeyEncrypted, secretKey, row.id, 'privateKey');
      passphrase = await _decryptField(row.passphraseEncrypted, secretKey, row.id, 'passphrase');
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

  Future<String?> _decryptField(
    String? ciphertext,
    SecretKey secretKey,
    String identityId,
    String field,
  ) async {
    if (ciphertext == null) return null;
    try {
      return await encryptionEngine.decrypt(
        encryptedBase64: ciphertext,
        secretKey: secretKey,
      );
    } on CryptoException {
      throw SecretDecryptionException(identityId, field);
    }
  }

  Future<void> deleteIdentity(String id) async {
    await identitiesDao.deleteIdentity(id);
  }

  Stream<List<Identity>> watchIdentities() {
    return identitiesDao.watchAllIdentities();
  }
}
