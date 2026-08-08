import 'dart:convert';

import '../../../../shared/storage/secure_storage_service.dart';
import '../../domain/models/device_link_pairing_profile.dart';

/// Secure-storage adapter for the mobile side of Device Link pairing.
final class DeviceLinkPairingStorage {
  static const _indexKey = 'device_link_profiles_index';
  final SecureStorageService storage;

  const DeviceLinkPairingStorage(this.storage);

  Future<List<DeviceLinkPairingProfile>> getAll() async {
    final rawIndex = await storage.getToken(_indexKey);
    if (rawIndex == null || rawIndex.isEmpty) return const [];
    final decoded = jsonDecode(rawIndex);
    if (decoded is! List) return const [];

    final profiles = <DeviceLinkPairingProfile>[];
    for (final id in decoded) {
      if (id is! String) continue;
      final raw = await storage.getToken(_profileKey(id));
      if (raw == null) continue;
      try {
        profiles.add(DeviceLinkPairingProfile.fromJson(jsonDecode(raw)));
      } catch (_) {
        // A corrupt profile should not prevent healthy pairings from loading.
      }
    }
    return profiles;
  }

  Future<DeviceLinkPairingProfile?> getById(String id) async {
    final raw = await storage.getToken(_profileKey(id));
    if (raw == null) return null;
    try {
      return DeviceLinkPairingProfile.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(DeviceLinkPairingProfile profile) async {
    await storage.saveToken(
      _profileKey(profile.id),
      jsonEncode(profile.toJson()),
    );
    final ids = (await _readIndex()).toSet()..add(profile.id);
    await _writeIndex(ids.toList()..sort());
  }

  Future<void> remove(String id) async {
    await storage.deleteToken(_profileKey(id));
    final ids = await _readIndex();
    ids.remove(id);
    await _writeIndex(ids);
  }

  Future<List<String>> _readIndex() async {
    final raw = await storage.getToken(_indexKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List && decoded.every((id) => id is String)) {
        return List<String>.from(decoded);
      }
    } catch (_) {}
    return [];
  }

  Future<void> _writeIndex(List<String> ids) {
    return storage.saveToken(_indexKey, jsonEncode(ids));
  }

  String _profileKey(String id) => 'device_link_profile_$id';
}
