import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Standard storage key definitions for [SecureStorageService].
abstract class SecureStorageKeys {
  static const String masterKey = 'terly2_master_key';
  static const String masterSalt = 'terly2_master_salt';
  static const String tokenPrefix = 'terly2_token_';
}

/// Secure Storage Service leveraging hardware-backed secure storage
/// (iOS Keychain, Android KeyStore, Windows Credential Manager, macOS Keychain, Linux Secret Service).
class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
              mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  /// Stores the 256-bit Master Key as a Base64 string in secure storage.
  Future<void> saveMasterKey(List<int> keyBytes) async {
    final base64Key = base64.encode(keyBytes);
    await _storage.write(key: SecureStorageKeys.masterKey, value: base64Key);
  }

  /// Retrieves the Master Key bytes from secure storage if present.
  Future<Uint8List?> getMasterKey() async {
    final base64Key = await _storage.read(key: SecureStorageKeys.masterKey);
    if (base64Key == null) return null;
    return Uint8List.fromList(base64.decode(base64Key));
  }

  /// Deletes the Master Key from secure storage.
  Future<void> deleteMasterKey() async {
    await _storage.delete(key: SecureStorageKeys.masterKey);
  }

  /// Stores the Master Salt bytes as a Base64 string in secure storage.
  Future<void> saveMasterSalt(Uint8List saltBytes) async {
    final base64Salt = base64.encode(saltBytes);
    await _storage.write(key: SecureStorageKeys.masterSalt, value: base64Salt);
  }

  /// Retrieves the Master Salt bytes from secure storage if present.
  Future<Uint8List?> getMasterSalt() async {
    final base64Salt = await _storage.read(key: SecureStorageKeys.masterSalt);
    if (base64Salt == null) return null;
    return Uint8List.fromList(base64.decode(base64Salt));
  }

  /// Deletes the Master Salt from secure storage.
  Future<void> deleteMasterSalt() async {
    await _storage.delete(key: SecureStorageKeys.masterSalt);
  }

  /// Stores a sensitive token (e.g. OAuth token, API token, session secret) under a key.
  Future<void> saveToken(String key, String token) async {
    final fullKey = key.startsWith(SecureStorageKeys.tokenPrefix)
        ? key
        : '${SecureStorageKeys.tokenPrefix}$key';
    await _storage.write(key: fullKey, value: token);
  }

  /// Retrieves a sensitive token by key.
  Future<String?> getToken(String key) async {
    final fullKey = key.startsWith(SecureStorageKeys.tokenPrefix)
        ? key
        : '${SecureStorageKeys.tokenPrefix}$key';
    return await _storage.read(key: fullKey);
  }

  /// Deletes a sensitive token by key.
  Future<void> deleteToken(String key) async {
    final fullKey = key.startsWith(SecureStorageKeys.tokenPrefix)
        ? key
        : '${SecureStorageKeys.tokenPrefix}$key';
    await _storage.delete(key: fullKey);
  }

  /// Writes an arbitrary key-value pair to secure storage.
  Future<void> write({required String key, required String value}) async {
    await _storage.write(key: key, value: value);
  }

  /// Reads an arbitrary key from secure storage.
  Future<String?> read({required String key}) async {
    return await _storage.read(key: key);
  }

  /// Deletes an arbitrary key from secure storage.
  Future<void> delete({required String key}) async {
    await _storage.delete(key: key);
  }

  /// Clears all stored key-value pairs in secure storage.
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }

  /// Checks if a key exists in secure storage.
  Future<bool> containsKey({required String key}) async {
    return await _storage.containsKey(key: key);
  }
}
