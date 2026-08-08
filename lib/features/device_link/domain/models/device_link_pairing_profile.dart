import '../../../../core/network/device_link/device_link_server.dart';

/// Secret and endpoint material retained on the mobile device after QR pairing.
///
/// The profile is serialized only into [SecureStorageService] by the storage
/// adapter; it is not a Drift row and must never be logged or sent back in a
/// QR code.
final class DeviceLinkPairingProfile {
  final String id;
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
    required String id,
    required String name,
    required String platform,
    required String secret,
    required DeviceLinkQrPayload payload,
    String? sessionId,
    DateTime? pairedAt,
  }) {
    return DeviceLinkPairingProfile(
      id: id,
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
    final sessionId = value['sessionId'];
    if (sessionId != null && sessionId is! String) {
      throw const FormatException(
        'Device Link pairing profile session id is invalid',
      );
    }
    return DeviceLinkPairingProfile(
      id: value['id'] as String,
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

  DeviceLinkPairingProfile copyWith({String? sessionId}) {
    return DeviceLinkPairingProfile(
      id: id,
      name: name,
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
