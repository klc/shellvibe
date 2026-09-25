import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/crypto/encryption_engine.dart';
import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/vault_env_vars_dao.dart';
import '../../domain/models/vault_env_var.dart';
import '../../domain/models/vault_env_var_rules.dart';
import '../vault_key_service.dart';

/// Thrown when a stored environment variable's value cannot be decrypted with
/// the current vault key.
class VaultEnvValueDecryptionException implements Exception {
  final String id;

  const VaultEnvValueDecryptionException(this.id);

  @override
  String toString() =>
      'VaultEnvValueDecryptionException: cannot decrypt the value of '
      'environment variable $id. It was encrypted with a different vault key.';
}

/// Thrown when a name fails validation: the wrong shape, reserved, or already
/// used elsewhere in the workspace.
class VaultEnvNameException implements Exception {
  final String message;

  const VaultEnvNameException(this.message);

  @override
  String toString() => message;
}

/// What resolving a workspace's environment variables for a new local shell
/// produced: the plaintext variables to set, whether the vault was locked (in
/// which case [vars] is always empty), and how many stored rows could not be
/// decrypted with the current key and were skipped.
typedef VaultEnvShellResolution = ({
  Map<String, String> vars,
  bool vaultLocked,
  int undecryptable,
});

class VaultEnvRepository {
  final VaultEnvVarsDao dao;
  final EncryptionEngine encryptionEngine;
  final VaultKeyService vaultKeyService;

  VaultEnvRepository({
    required this.dao,
    required this.encryptionEngine,
    required this.vaultKeyService,
  });

  /// Lists a workspace's environment variables. With [decrypt] the values are
  /// decrypted best-effort: a row that cannot be read comes back with a null
  /// value rather than failing the whole list.
  Future<List<VaultEnvVarModel>> list({
    required String workspaceId,
    bool decrypt = false,
  }) async {
    final rows = await dao.getByWorkspace(workspaceId);

    SecretKey? secretKey;
    if (decrypt) {
      secretKey = await vaultKeyService.getDek();
    }

    final result = <VaultEnvVarModel>[];
    for (final row in rows) {
      String? value;
      if (decrypt && secretKey != null) {
        try {
          value = await encryptionEngine.decrypt(
            encryptedBase64: row.valueEncrypted,
            secretKey: secretKey,
          );
        } on CryptoException {
          value = null;
        }
      }
      result.add(
        VaultEnvVarModel(
          id: row.id,
          workspaceId: row.workspaceId,
          name: row.name,
          value: value,
          createdAt: row.createdAt,
        ),
      );
    }
    return result;
  }

  /// Decrypts a single variable's value, for the row-level "reveal" control.
  ///
  /// Throws [VaultEnvValueDecryptionException] when the ciphertext cannot be
  /// read with the current vault key. Returns null when [id] does not exist.
  Future<String?> decryptValue(String id) async {
    final row = await dao.getById(id);
    if (row == null) return null;

    final secretKey = await vaultKeyService.getDek();
    try {
      return await encryptionEngine.decrypt(
        encryptedBase64: row.valueEncrypted,
        secretKey: secretKey,
      );
    } on CryptoException {
      throw VaultEnvValueDecryptionException(id);
    }
  }

  /// Creates or updates a variable, validating and encrypting [value].
  ///
  /// Throws [VaultEnvNameException] for a malformed, reserved, or (within the
  /// workspace) duplicate name.
  Future<VaultEnvVarModel> save({
    String? id,
    required String workspaceId,
    required String name,
    required String value,
  }) async {
    final trimmedName = name.trim();
    if (!vaultEnvVarNameRegex.hasMatch(trimmedName)) {
      throw const VaultEnvNameException(
        'Use letters, numbers and underscores, starting with a letter or '
        'underscore.',
      );
    }
    if (kReservedVaultEnvVarNames.contains(trimmedName)) {
      throw VaultEnvNameException(
        '"$trimmedName" is set automatically and cannot be overridden.',
      );
    }

    final existing = await dao.getByWorkspace(workspaceId);
    final isDuplicate = existing.any(
      (row) => row.name == trimmedName && row.id != id,
    );
    if (isDuplicate) {
      throw VaultEnvNameException(
        'A variable named "$trimmedName" already exists in this workspace.',
      );
    }

    final secretKey = await vaultKeyService.getDek();
    final encryptedValue = await encryptionEngine.encrypt(
      plaintext: value,
      secretKey: secretKey,
    );

    final varId = id ?? const Uuid().v4();
    final now = DateTime.now();

    final companion = VaultEnvVarsCompanion(
      id: Value(varId),
      workspaceId: Value(workspaceId),
      name: Value(trimmedName),
      valueEncrypted: Value(encryptedValue),
      // Keep the original creation date on edits.
      createdAt: id == null ? Value(now) : const Value.absent(),
    );

    if (id == null) {
      await dao.insert(companion);
    } else {
      final updated = await dao.updateById(varId, companion);
      if (updated != 1) {
        throw StateError('Environment variable not found: $varId');
      }
    }

    return VaultEnvVarModel(
      id: varId,
      workspaceId: workspaceId,
      name: trimmedName,
      value: value,
      createdAt: now,
    );
  }

  Future<void> delete(String id) async {
    await dao.deleteById(id);
  }

  /// Resolves the environment variables a new local shell in [workspaceId]
  /// should start with.
  ///
  /// Never touches the vault key when the workspace has no rows: `getDek()`
  /// reads secure storage — in a protected, locked vault that throws, and in
  /// a widget test it never completes at all, which would leave every local
  /// shell in a workspace with no stored variables "connecting" forever. Both
  /// are worse than the one extra query this does instead.
  Future<VaultEnvShellResolution> resolveForShell({
    required String workspaceId,
  }) async {
    final rows = await dao.getByWorkspace(workspaceId);
    if (rows.isEmpty) {
      return (
        vars: const <String, String>{},
        vaultLocked: false,
        undecryptable: 0,
      );
    }

    final SecretKey secretKey;
    try {
      secretKey = await vaultKeyService.getDek();
    } on VaultLockedException {
      return (
        vars: const <String, String>{},
        vaultLocked: true,
        undecryptable: 0,
      );
    }

    // Rows are validated when saved here, but a row that arrived by sync or
    // restore was not: one that could not have been saved locally is skipped
    // rather than handed to the shell. A name two devices both added offline
    // resolves to the newest row, so every device picks the same value.
    final usable =
        rows
            .where(
              (row) =>
                  vaultEnvVarNameRegex.hasMatch(row.name) &&
                  !kReservedVaultEnvVarNames.contains(row.name),
            )
            .toList()
          ..sort((a, b) {
            final byDate = a.createdAt.compareTo(b.createdAt);
            return byDate != 0 ? byDate : a.id.compareTo(b.id);
          });

    final vars = <String, String>{};
    var undecryptable = 0;
    for (final row in usable) {
      try {
        vars[row.name] = await encryptionEngine.decrypt(
          encryptedBase64: row.valueEncrypted,
          secretKey: secretKey,
        );
      } on CryptoException {
        undecryptable++;
      }
    }

    return (vars: vars, vaultLocked: false, undecryptable: undecryptable);
  }
}
