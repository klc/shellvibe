import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../../core/network/device_link/device_link_protocol.dart';
import '../../../../shared/storage/secure_storage_service.dart';
import '../../domain/models/device_link_pairing_profile.dart';

/// Secure-storage adapter for the mobile side of Device Link pairing.
final class DeviceLinkPairingStorage {
  static const _indexKey = 'device_link_profiles_index';
  final SecureStorageService storage;

  const DeviceLinkPairingStorage(this.storage);

  /// This install's client device id, created on first use and kept.
  ///
  /// The desktop identifies a phone by this id: it is how a rescan, an app
  /// restart or a network flip is recognised as the *same* phone coming back
  /// to a session it already owns, rather than as a stranger asking for a
  /// session that is in use. A fresh id per pairing also leaves one dead
  /// profile behind per scan, each of which auto-reconnect then dials.
  Future<String> deviceId({String Function()? generate}) async {
    final existing = await storage.getToken(
      SecureStorageKeys.deviceLinkClientDeviceId,
    );
    if (existing != null && existing.isNotEmpty) return existing;
    final created = (generate ?? const Uuid().v4)();
    await storage.saveToken(
      SecureStorageKeys.deviceLinkClientDeviceId,
      created,
    );
    return created;
  }

  Future<List<DeviceLinkPairingProfile>> getAll() async {
    // A half-written or migrated index must not take auto-reconnect down with
    // it: the callers are fire-and-forget, so a decode throwing here escapes
    // the zone and no pairing ever reconnects again.
    final decoded = await _readIndex();

    final profiles = <DeviceLinkPairingProfile>[];
    for (final id in decoded) {
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

  /// Pairings this phone holds with one desktop, newest first.
  Future<List<DeviceLinkPairingProfile>> profilesForDesktop(String spki) async {
    final profiles = (await getAll())
        .where((profile) => profile.spki == spki)
        .toList();
    profiles.sort((left, right) => right.pairedAt.compareTo(left.pairedAt));
    return profiles;
  }

  /// Claims the desktop can use to retire rows this phone paired under an
  /// earlier client id.
  ///
  /// Only pairings with that same desktop are considered: a secret is issued by
  /// one desktop and proves nothing to another, so handing it to a different
  /// peer would leak it for no gain. Entries are capped at what a pair frame
  /// may carry, keeping the newest — the ids most likely to still exist there.
  Future<List<DeviceLinkSupersededDevice>> supersededDeviceClaims({
    required String spki,
    required String deviceId,
  }) async {
    final claims = <DeviceLinkSupersededDevice>[];
    final seen = <String>{deviceId};
    for (final profile in await profilesForDesktop(spki)) {
      if (!seen.add(profile.deviceId)) continue;
      claims.add(
        DeviceLinkSupersededDevice(
          deviceId: profile.deviceId,
          secret: profile.secret,
        ),
      );
      if (claims.length == deviceLinkMaxSupersededDevices) break;
    }
    return claims;
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

  /// Drops pairings with the same desktop that were made under a different
  /// client id.
  ///
  /// Before the client id was persisted, every scan produced a new one and left
  /// its profile behind. Auto-reconnect dials each of them, so those ghosts do
  /// not just sit there: they open connections and compete for the very session
  /// this phone is trying to attach to.
  Future<void> pruneSupersededProfiles({
    required String keepId,
    required String spki,
  }) async {
    for (final profile in await getAll()) {
      if (profile.id == keepId || profile.spki != spki) continue;
      await remove(profile.id);
    }
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
