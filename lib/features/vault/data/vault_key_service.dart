import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../core/crypto/encryption_engine.dart';
import '../../../shared/storage/secure_storage_service.dart';

/// Thrown when a secret operation is attempted while a master-password
/// protected vault is still locked.
class VaultLockedException implements Exception {
  const VaultLockedException();

  @override
  String toString() =>
      'VaultLockedException: the vault is locked. Unlock it with the master password first.';
}

/// Owns the vault Data Encryption Key (DEK) and its two protection modes.
///
/// The DEK is a random 256-bit key that encrypts every identity secret. It is
/// generated once and **never rotated**, so enabling or disabling the master
/// password never requires re-encrypting stored data.
///
/// Two modes:
/// * **No master password** — the DEK is stored directly in the OS keychain
///   ([SecureStorageKeys.masterKey]) and is available without user interaction.
/// * **Master password configured** — a Key Encryption Key (KEK) is derived from
///   the password with Argon2id, the DEK is stored only in its AES-256-GCM
///   wrapped form ([SecureStorageKeys.wrappedDek]) and the plaintext copy is
///   deleted from the keychain. The unwrapped DEK then lives in memory only,
///   until [lock] is called.
class VaultKeyService {
  final EncryptionEngine encryptionEngine;
  final SecureStorageService secureStorageService;

  SecretKey? _unlockedDek;

  VaultKeyService({
    required this.encryptionEngine,
    required this.secureStorageService,
  });

  /// True when a master password protects the DEK.
  Future<bool> isMasterPasswordConfigured() async {
    return secureStorageService.containsKey(key: SecureStorageKeys.masterSalt);
  }

  /// True when the vault is protected and currently unlocked in memory.
  bool get isUnlockedInMemory => _unlockedDek != null;

  /// Returns the DEK, creating it on first use in unprotected mode.
  ///
  /// Throws [VaultLockedException] when a master password is configured and the
  /// vault has not been unlocked yet.
  Future<SecretKey> getDek() async {
    if (await isMasterPasswordConfigured()) {
      final dek = _unlockedDek;
      if (dek == null) throw const VaultLockedException();
      return dek;
    }

    final existing = await secureStorageService.getMasterKey();
    if (existing != null) return SecretKey(existing);

    final generated = encryptionEngine.generateKey();
    await secureStorageService.saveMasterKey(generated);
    return SecretKey(generated);
  }

  /// Protects the existing DEK with [masterPassword].
  ///
  /// Preserves the current DEK, so identities encrypted before the master
  /// password was set remain decryptable. Leaves the vault unlocked.
  Future<void> configureMasterPassword(String masterPassword) async {
    if (await isMasterPasswordConfigured()) {
      throw StateError('A master password is already configured.');
    }

    // Reuse the plaintext DEK if present, otherwise create one now.
    final dek = await getDek();
    final dekBytes = await dek.extractBytes();

    final salt = encryptionEngine.generateSalt();
    final kek = await encryptionEngine.deriveMasterKeyInBackground(
      masterPassword: masterPassword,
      salt: salt,
    );
    final wrapped = await encryptionEngine.encrypt(
      plaintext: base64.encode(dekBytes),
      secretKey: kek,
    );

    await secureStorageService.write(
      key: SecureStorageKeys.wrappedDek,
      value: wrapped,
    );
    await secureStorageService.saveMasterSalt(salt);
    // The plaintext copy must go away, otherwise the master password is cosmetic.
    await secureStorageService.deleteMasterKey();

    _unlockedDek = SecretKey(dekBytes);
  }

  /// Unwraps the DEK with [masterPassword]. Returns false on a wrong password.
  Future<bool> unlock(String masterPassword) async {
    final salt = await secureStorageService.getMasterSalt();
    final wrapped =
        await secureStorageService.read(key: SecureStorageKeys.wrappedDek);
    if (salt == null || wrapped == null) return false;

    final kek = await encryptionEngine.deriveMasterKeyInBackground(
      masterPassword: masterPassword,
      salt: salt,
    );

    try {
      final dekBase64 = await encryptionEngine.decrypt(
        encryptedBase64: wrapped,
        secretKey: kek,
      );
      _unlockedDek = SecretKey(Uint8List.fromList(base64.decode(dekBase64)));
      return true;
    } on CryptoException {
      // AES-GCM MAC failure == wrong password.
      return false;
    }
  }

  /// Drops the unwrapped DEK from memory.
  void lock() {
    _unlockedDek = null;
  }

  /// Removes master-password protection, returning the DEK to the keychain.
  ///
  /// Requires the vault to be unlocked so the DEK can be recovered.
  Future<void> removeMasterPassword() async {
    final dek = _unlockedDek;
    if (dek == null) throw const VaultLockedException();

    await secureStorageService.saveMasterKey(await dek.extractBytes());
    await secureStorageService.delete(key: SecureStorageKeys.wrappedDek);
    await secureStorageService.deleteMasterSalt();
  }
}
