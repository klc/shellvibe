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
}

/// Secure Storage Service leveraging hardware-backed secure storage
/// (iOS Keychain, Android KeyStore, Windows Credential Manager, macOS Keychain, Linux Secret Service)
/// with in-memory fallback for un-entitled macOS environment (-34018).
class SecureStorageService {
  final FlutterSecureStorage _storage;
  final Map<String, String> _inMemoryFallback = {};

  SecureStorageService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              migrateOnAlgorithmChange: true,
              migrateWithBackup: true,
            ),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
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
