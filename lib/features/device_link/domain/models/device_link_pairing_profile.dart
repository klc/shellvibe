import '../../../../core/network/device_link/device_link_server.dart';

/// Secret and endpoint material retained on the mobile device after QR pairing.
///
/// The profile is serialized only into [SecureStorageService] by the storage
/// adapter; it is not a Drift row and must never be logged or sent back in a
/// QR code.
final class DeviceLinkPairingProfile {
  /// Identifies the *desktop* this pairing is with, so one phone can hold a
  /// profile per desktop. The storage adapter keys records by it.
  final String id;

  /// Identifies *this phone* to the desktop, and is stable across pairings —
  /// it is how a desktop recognises the same phone coming back to a session it
  /// already owns. Distinct from [id]: a phone has one of these and as many
  /// profiles as it has desktops.
  final String deviceId;

  final String name;
  final String platform;
  final String secret;
  final String host;
  final List<String> addresses;
  final String mdns;
  final int port;
  final String spki;
  final String? sessionId;
  final DateTime pairedAt;

  DeviceLinkPairingProfile({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.secret,
    required this.host,
    required List<String> addresses,
    required this.mdns,
    required this.port,
    required this.spki,
    required this.sessionId,
    required this.pairedAt,
  }) : addresses = List.unmodifiable(addresses);

  factory DeviceLinkPairingProfile.fromQr({
    required String deviceId,
    required String name,
    required String platform,
    required String secret,
    required DeviceLinkQrPayload payload,
    String? sessionId,
    DateTime? pairedAt,
  }) {
    return DeviceLinkPairingProfile(
      // The desktop's public-key pin is its identity, and the one part of the
      // payload that cannot change behind our back: a desktop that moves to
      // another address or port is still the same pairing, and re-pairing it
      // replaces the profile instead of accumulating one per scan.
      id: payload.spki,
      deviceId: deviceId,
      name: name,
      platform: platform,
      secret: secret,
      host: payload.host,
      addresses: payload.addresses,
      mdns: payload.mdns,
      port: payload.port,
      spki: payload.spki,
      sessionId: sessionId,
      pairedAt: (pairedAt ?? DateTime.now()).toUtc(),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'deviceId': deviceId,
    'name': name,
    'platform': platform,
    'secret': secret,
    'host': host,
    'addresses': addresses,
    'mdns': mdns,
    'port': port,
    'spki': spki,
    'sessionId': sessionId,
    'pairedAt': pairedAt.toUtc().toIso8601String(),
  };

  factory DeviceLinkPairingProfile.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException(
        'Device Link pairing profile must be an object',
      );
    }
    final rawAddresses = value['addresses'];
    final pairedAt = DateTime.tryParse(value['pairedAt'] as String? ?? '');
    if (value['id'] is! String ||
        value['name'] is! String ||
        value['platform'] is! String ||
        value['secret'] is! String ||
        value['host'] is! String ||
        rawAddresses is! List ||
        rawAddresses.any((item) => item is! String) ||
        value['mdns'] is! String ||
        value['port'] is! int ||
        value['spki'] is! String ||
        pairedAt == null) {
      throw const FormatException(
        'Device Link pairing profile has invalid fields',
      );
    }
    final deviceId = value['deviceId'];
    if (deviceId != null && deviceId is! String) {
      throw const FormatException(
        'Device Link pairing profile device id is invalid',
      );
    }
    final sessionId = value['sessionId'];
    if (sessionId != null && sessionId is! String) {
      throw const FormatException(
        'Device Link pairing profile session id is invalid',
      );
    }
    return DeviceLinkPairingProfile(
      id: value['id'] as String,
      // Profiles written before the phone had a lasting identity keyed both
      // roles off the same value, so the record's own id is the device id it
      // paired under. Keeping it means those pairings keep authenticating.
      deviceId: (deviceId as String?) ?? value['id'] as String,
      name: value['name'] as String,
      platform: value['platform'] as String,
      secret: value['secret'] as String,
      host: value['host'] as String,
      addresses: List<String>.from(rawAddresses),
      mdns: value['mdns'] as String,
      port: value['port'] as int,
      spki: value['spki'] as String,
      sessionId: sessionId as String?,
      pairedAt: pairedAt.toUtc(),
    );
  }

  DeviceLinkPairingProfile copyWith({String? sessionId, String? name}) {
    return DeviceLinkPairingProfile(
      id: id,
      deviceId: deviceId,
      name: name ?? this.name,
      platform: platform,
      secret: secret,
      host: host,
      addresses: addresses,
      mdns: mdns,
      port: port,
      spki: spki,
      sessionId: sessionId ?? this.sessionId,
      pairedAt: pairedAt,
    );
  }
}
