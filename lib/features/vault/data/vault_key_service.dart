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

/// Thrown when the vault key is gone from the keychain while what it
/// encrypted is still here.
///
/// A keystore reset, a device-to-device transfer that carried the database
/// but not the key, or a keychain item deleted by hand all end here. A new
/// key would open none of the existing secrets, so none is made: the user
/// resets the vault instead, knowingly.
class VaultKeyLostException implements Exception {
  const VaultKeyLostException();

  @override
  String toString() =>
      'VaultKeyLostException: the vault key is missing from the keychain, '
      'but secrets encrypted with it are still stored. Reset the vault to '
      'start over.';
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

  /// Whether the database holds anything encrypted under the DEK. Asked only
  /// when the keychain has no key, to tell a first run from a lost key.
  final Future<bool> Function()? hasEncryptedData;

  SecretKey? _unlockedDek;
  int _lifecycleGeneration = 0;

  /// The unprotected read-or-create in progress, shared by every caller that
  /// arrives while it runs.
  Future<SecretKey>? _plainDek;

  VaultKeyService({
    required this.encryptionEngine,
    required this.secureStorageService,
    this.hasEncryptedData,
  });

  /// True when a master password protects the DEK.
  Future<bool> isMasterPasswordConfigured() async {
    return secureStorageService.containsKey(key: SecureStorageKeys.masterSalt);
  }

  /// True when the key that opens this vault's data is gone. See
  /// [VaultKeyLostException].
  Future<bool> isKeyLost() async {
    if (await isMasterPasswordConfigured()) {
      return !await secureStorageService.containsKey(
        key: SecureStorageKeys.wrappedDek,
      );
    }
    if (await secureStorageService.getMasterKey() != null) return false;
    return _plainKeyLost();
  }

  /// No plaintext key, yet something says there was one: a wrapped copy
  /// whose salt went missing, or encrypted rows.
  Future<bool> _plainKeyLost() async =>
      await secureStorageService.containsKey(
        key: SecureStorageKeys.wrappedDek,
      ) ||
      (await hasEncryptedData?.call() ?? false);

  /// True when the vault is protected and currently unlocked in memory.
  bool get isUnlockedInMemory => _unlockedDek != null;

  /// Returns the DEK, creating it on first use in unprotected mode.
  ///
  /// Throws [VaultLockedException] when a master password is configured and the
  /// vault has not been unlocked yet, and [VaultKeyLostException] when there
  /// is no key but there is data encrypted under one.
  Future<SecretKey> getDek() async {
    if (await isMasterPasswordConfigured()) {
      final dek = _unlockedDek;
      if (dek == null) throw const VaultLockedException();
      return dek;
    }

    // One at a time. Two callers that both read an empty keychain would each
    // generate a key, and the second save overwrites the first: whatever was
    // encrypted under it -- an identity saved, one arriving by sync -- can
    // never be opened again. Cleared once done, so a later call reads the
    // keychain again rather than a key that may since have been replaced.
    final running = _plainDek;
    if (running != null) return running;

    final started = _readOrCreatePlainDek();
    _plainDek = started;
    try {
      return await started;
    } finally {
      if (identical(_plainDek, started)) _plainDek = null;
    }
  }

  Future<SecretKey> _readOrCreatePlainDek() async {
    final existing = await secureStorageService.getMasterKey();
    if (existing != null) return SecretKey(existing);
    if (await _plainKeyLost()) throw const VaultKeyLostException();

    final generated = encryptionEngine.generateKey();
    await secureStorageService.saveMasterKey(generated);
    return SecretKey(generated);
  }

  /// Protects the existing DEK with [masterPassword].
  ///
  /// Preserves the current DEK, so identities encrypted before the master
  /// password was set remain decryptable. Leaves the vault unlocked.
  Future<void> configureMasterPassword(String masterPassword) async {
    final generation = _lifecycleGeneration;
    if (await isMasterPasswordConfigured()) {
      throw StateError('A master password is already configured.');
    }

    // Reuse the plaintext DEK if present, otherwise create one now.
    final dek = await getDek();
    final dekBytes = await dek.extractBytes();

    final salt = encryptionEngine.generateSalt();
    final params = encryptionEngine.kdfParams;
    final kek = await encryptionEngine.deriveMasterKeyInBackground(
      masterPassword: masterPassword,
      salt: salt,
      params: params,
    );
    final wrapped = await encryptionEngine.encrypt(
      plaintext: base64.encode(dekBytes),
      secretKey: kek,
    );

    await secureStorageService.write(
      key: SecureStorageKeys.wrappedDek,
      value: wrapped,
    );
    await secureStorageService.write(
      key: SecureStorageKeys.masterKdf,
      value: jsonEncode(params.toJson()),
    );
    // The salt is the mode flag, so it goes last.
    await secureStorageService.saveMasterSalt(salt);

    // The plaintext copy is the only way back, so before it goes, open what
    // was just stored the way the next launch will: read back and derived
    // again from the password as typed. A write the keychain dropped or
    // garbled must not cost the vault.
    final reopened = await _unwrap(masterPassword);
    if (reopened == null || !constantTimeEquals(reopened, dekBytes)) {
      await _forgetWrappedKey();
      throw StateError(
        'The master password could not be verified. Nothing was changed.',
      );
    }

    // The plaintext copy must go away, otherwise the master password is cosmetic.
    await secureStorageService.deleteMasterKey();

    // lock() may have been called while Argon2id was running. Do not restore
    // a plaintext DEK after that lock has already invalidated this operation.
    if (generation == _lifecycleGeneration) {
      _unlockedDek = SecretKey(dekBytes);
    }
  }

  /// Unwraps the DEK with [masterPassword]. Returns false on a wrong password.
  Future<bool> unlock(String masterPassword) async {
    final generation = _lifecycleGeneration;
    final dek = await _unwrap(masterPassword);
    if (dek == null || generation != _lifecycleGeneration) return false;
    _unlockedDek = SecretKey(dek);

    // A setup that stopped between wrapping the key and deleting the
    // plaintext copy left that copy behind, and nothing else removes it.
    if (await secureStorageService.containsKey(
      key: SecureStorageKeys.masterKey,
    )) {
      await secureStorageService.deleteMasterKey();
    }
    return true;
  }

  /// The DEK as stored under [masterPassword], or null when the password is
  /// wrong or nothing is stored.
  Future<Uint8List?> _unwrap(String masterPassword) async {
    final salt = await secureStorageService.getMasterSalt();
    final wrapped = await secureStorageService.read(
      key: SecureStorageKeys.wrappedDek,
    );
    if (salt == null || wrapped == null) return null;
    final storedParams = await secureStorageService.read(
      key: SecureStorageKeys.masterKdf,
    );

    final kek = await encryptionEngine.deriveMasterKeyInBackground(
      masterPassword: masterPassword,
      salt: salt,
      params: storedParams == null
          ? Argon2Params.legacy
          : Argon2Params.fromJson(
              jsonDecode(storedParams) as Map<String, dynamic>,
            ),
    );

    try {
      final dekBase64 = await encryptionEngine.decrypt(
        encryptedBase64: wrapped,
        secretKey: kek,
      );
      return Uint8List.fromList(base64.decode(dekBase64));
    } on CryptoException {
      // AES-GCM MAC failure == wrong password.
      return null;
    }
  }

  /// Drops the wrapped key, salt first: the salt is the mode flag, so a
  /// crash part-way leaves plain mode with a harmless leftover.
  Future<void> _forgetWrappedKey() async {
    await secureStorageService.deleteMasterSalt();
    await secureStorageService.delete(key: SecureStorageKeys.wrappedDek);
    await secureStorageService.delete(key: SecureStorageKeys.masterKdf);
  }

  /// Drops the unwrapped DEK from memory.
  void lock() {
    _lifecycleGeneration++;
    _unlockedDek = null;
  }

  /// Removes master-password protection, returning the DEK to the keychain.
  ///
  /// Requires the vault to be unlocked so the DEK can be recovered.
  Future<void> removeMasterPassword() async {
    final dek = _unlockedDek;
    if (dek == null) throw const VaultLockedException();

    await secureStorageService.saveMasterKey(await dek.extractBytes());
    await _forgetWrappedKey();
  }

  /// Forgets the DEK in every form it is stored in, for a vault reset.
  ///
  /// Whatever it encrypted can never be opened again; the caller discards
  /// those secrets. The next [getDek] creates a new key.
  Future<void> reset() async {
    lock();
    await _forgetWrappedKey();
    await secureStorageService.deleteMasterKey();
  }
}
