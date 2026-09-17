import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Standard storage key definitions for [SecureStorageService].
abstract class SecureStorageKeys {
  /// Plaintext Data Encryption Key. Present only while no master password is set.
  static const String masterKey = 'shellvibe_master_key';

  /// Argon2id salt for the master password. Its presence means the vault is protected.
  static const String masterSalt = 'shellvibe_master_salt';

  /// DEK wrapped with the master-password-derived KEK.
  static const String wrappedDek = 'shellvibe_wrapped_dek';
  static const String vaultFailedAttempts = 'shellvibe_vault_failed_attempts';
  static const String vaultLockoutUntil = 'shellvibe_vault_lockout_until';
  static const String tokenPrefix = 'shellvibe_token_';
  static const String deviceLinkServerIdentity = 'device_link_server_identity';

  /// This install's Device Link identity as a *client*. It has to outlive a
  /// single pairing: a desktop recognises a returning phone by this id, and a
  /// phone that invents a new one every time it scans looks like a new device
  /// on every pairing — one that cannot take back the session its previous
  /// identity still holds.
  static const String deviceLinkClientDeviceId = 'device_link_client_device_id';

  /// Sanctum bearer token for the ShellVibe Server account session.
  static const String accountToken = 'shellvibe_account_token';

  /// The server's ULID for *this* install's device record.
  ///
  /// Has to be durable across sign-ins: `POST /auth/login` opens a brand new
  /// device record whenever the request arrives without a `device_id`, so an
  /// install that forgets this id shows up as a new device on every sign-in
  /// and inflates the account's device list.
  static const String accountDeviceId = 'shellvibe_account_device_id';

  /// The server's ULID for the signed-in user. Also the RevenueCat
  /// `appUserId`, which is how a purchase webhook finds the right account.
  static const String accountUserId = 'shellvibe_account_user_id';

  /// Cached account email, so the sign-in form can prefill after a token is
  /// revoked. Not a credential.
  static const String accountEmail = 'shellvibe_account_email';
}

/// Secure Storage Service leveraging hardware-backed secure storage
/// (iOS Keychain, Android KeyStore, Windows Credential Manager, macOS Keychain, Linux Secret Service)
/// with in-memory fallback for un-entitled macOS environment (-34018).
class SecureStorageService {
  final FlutterSecureStorage _storage;
  final Map<String, String> _inMemoryFallback = {};

  /// Platform options the app stores secrets under.
  ///
  /// Named constants rather than inline arguments so a test can reach the real
  /// keychain with exactly these, instead of testing a configuration nothing
  /// ships with.
  static const macOsOptions = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock,
    // The data protection keychain, which this defaults to, is reachable only
    // by a binary whose signature carries a `keychain-access-groups`
    // entitlement — and that entitlement in turn needs a team identifier. An
    // ad-hoc signed build has neither, and every write comes back
    // errSecMissingEntitlement (-34018): "Save Identity Error" on the first key
    // a user adds.
    //
    // The file-based keychain needs no entitlement and works the same whether
    // or not the app is signed, which is why the choice is made here rather
    // than left to how a particular build was produced. Items still live
    // encrypted in the user's login keychain, gated by their login password and
    // an ACL macOS prompts about; what is given up is the per-item isolation
    // the data protection keychain adds on top.
    usesDataProtectionKeychain: false,
  );

  static const iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  static const androidOptions = AndroidOptions(
    migrateOnAlgorithmChange: true,
    migrateWithBackup: true,
  );

  SecureStorageService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: androidOptions,
            iOptions: iosOptions,
            mOptions: macOsOptions,
          );

  bool _isEntitlementError(Object e) {
    // In release builds an entitlement failure means provisioning is broken:
    // silently falling back to an in-memory map would leave secrets in plain
    // RAM for the whole session. Only tolerate the fallback in debug/profile.
    if (kReleaseMode) return false;
    if (e is PlatformException) {
      return e.code == '-34018' ||
          (e.message != null && e.message!.contains('-34018')) ||
          (e.message != null && e.message!.contains('entitlement'));
    }
    return false;
  }

  /// Stores the 256-bit Master Key as a Base64 string in secure storage.
  Future<void> saveMasterKey(List<int> keyBytes) async {
    final base64Key = base64.encode(keyBytes);
    await write(key: SecureStorageKeys.masterKey, value: base64Key);
  }

  /// Retrieves the Master Key bytes from secure storage if present.
  Future<Uint8List?> getMasterKey() async {
    final base64Key = await read(key: SecureStorageKeys.masterKey);
    if (base64Key == null) return null;
    return Uint8List.fromList(base64.decode(base64Key));
  }

  /// Deletes the Master Key from secure storage.
  Future<void> deleteMasterKey() async {
    await delete(key: SecureStorageKeys.masterKey);
  }

  /// Stores the Master Salt bytes as a Base64 string in secure storage.
  Future<void> saveMasterSalt(Uint8List saltBytes) async {
    final base64Salt = base64.encode(saltBytes);
    await write(key: SecureStorageKeys.masterSalt, value: base64Salt);
  }

  /// Retrieves the Master Salt bytes from secure storage if present.
  Future<Uint8List?> getMasterSalt() async {
    final base64Salt = await read(key: SecureStorageKeys.masterSalt);
    if (base64Salt == null) return null;
    return Uint8List.fromList(base64.decode(base64Salt));
  }

  /// Deletes the Master Salt from secure storage.
  Future<void> deleteMasterSalt() async {
    await delete(key: SecureStorageKeys.masterSalt);
  }

  /// Stores a sensitive token (e.g. OAuth token, API token, session secret) under a key.
  Future<void> saveToken(String key, String token) async {
    final fullKey = key.startsWith(SecureStorageKeys.tokenPrefix)
        ? key
        : '${SecureStorageKeys.tokenPrefix}$key';
    await write(key: fullKey, value: token);
  }

  /// Retrieves a sensitive token by key.
  Future<String?> getToken(String key) async {
    final fullKey = key.startsWith(SecureStorageKeys.tokenPrefix)
        ? key
        : '${SecureStorageKeys.tokenPrefix}$key';
    return await read(key: fullKey);
  }

  /// Deletes a sensitive token by key.
  Future<void> deleteToken(String key) async {
    final fullKey = key.startsWith(SecureStorageKeys.tokenPrefix)
        ? key
        : '${SecureStorageKeys.tokenPrefix}$key';
    await delete(key: fullKey);
  }

  /// Writes an arbitrary key-value pair to secure storage.
  Future<void> write({required String key, required String value}) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      if (_isEntitlementError(e)) {
        _inMemoryFallback[key] = value;
      } else {
        rethrow;
      }
    }
  }

  /// Reads an arbitrary key from secure storage.
  Future<String?> read({required String key}) async {
    try {
      final value = await _storage.read(key: key) ?? _inMemoryFallback[key];
      if (value != null) return value;
      if (key.startsWith('shellvibe_')) {
        final legacyKey = 'terly2_${key.substring('shellvibe_'.length)}';
        final legacyValue =
            await _storage.read(key: legacyKey) ?? _inMemoryFallback[legacyKey];
        if (legacyValue != null) {
          await write(key: key, value: legacyValue);
          return legacyValue;
        }
      }
      return null;
    } catch (e) {
      if (_isEntitlementError(e)) {
        return _inMemoryFallback[key];
      }
      rethrow;
    }
  }

  /// Deletes an arbitrary key from secure storage.
  Future<void> delete({required String key}) async {
    try {
      await _storage.delete(key: key);
      _inMemoryFallback.remove(key);
    } catch (e) {
      if (_isEntitlementError(e)) {
        _inMemoryFallback.remove(key);
      } else {
        rethrow;
      }
    }
  }

  /// Clears all stored key-value pairs in secure storage.
  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
      _inMemoryFallback.clear();
    } catch (e) {
      if (_isEntitlementError(e)) {
        _inMemoryFallback.clear();
      } else {
        rethrow;
      }
    }
  }

  /// Checks if a key exists in secure storage.
  Future<bool> containsKey({required String key}) async {
    try {
      final exists = await _storage.containsKey(key: key);
      if (exists || _inMemoryFallback.containsKey(key)) return true;
      if (key.startsWith('shellvibe_')) {
        final legacyKey = 'terly2_${key.substring('shellvibe_'.length)}';
        return await _storage.containsKey(key: legacyKey) ||
            _inMemoryFallback.containsKey(legacyKey);
      }
      return false;
    } catch (e) {
      if (_isEntitlementError(e)) {
        return _inMemoryFallback.containsKey(key);
      }
      rethrow;
    }
  }
}
