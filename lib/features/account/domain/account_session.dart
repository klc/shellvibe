import 'package:flutter/foundation.dart';

/// The account and device identity behind an active server session.
///
/// Holds no bearer token: the token lives only in
/// [SecureStorageService] and is read per request by the API client, so it
/// cannot be captured in a widget tree, a provider snapshot or an error report.
@immutable
final class AccountSession {
  /// Server ULID of the user. Also the RevenueCat `appUserId`.
  final String userId;

  /// Server ULID of this install's device record.
  final String deviceId;

  final String email;

  /// Display name on the account.
  final String name;

  const AccountSession({
    required this.userId,
    required this.deviceId,
    required this.email,
    required this.name,
  });

  @override
  bool operator ==(Object other) =>
      other is AccountSession &&
      other.userId == userId &&
      other.deviceId == deviceId &&
      other.email == email &&
      other.name == name;

  @override
  int get hashCode => Object.hash(userId, deviceId, email, name);

  @override
  String toString() => 'AccountSession($email, device: $deviceId)';
}

/// A device registered to the account, as `GET /devices` reports it.
@immutable
final class AccountDevice {
  final String id;
  final String name;

  /// One of `ios`, `android`, `macos`, `windows`, `linux`, `web`.
  ///
  /// Kept as a string rather than an enum: the contract says new enum values
  /// may appear within v1 and that the client must be fail-safe about them, and
  /// an unknown platform should render as itself rather than crash a list.
  final String platform;

  final String? appVersion;
  final DateTime? lastSeenAt;

  /// Set when the server has revoked this device's tokens.
  final DateTime? revokedAt;

  const AccountDevice({
    required this.id,
    required this.name,
    required this.platform,
    this.appVersion,
    this.lastSeenAt,
    this.revokedAt,
  });

  bool get isRevoked => revokedAt != null;

  /// Decodes a device DTO from a `data` member.
  ///
  /// Only `id` is required. Everything else falls back, because the contract
  /// allows backward-compatible field additions and removals only via `/v2` --
  /// but a client that throws on a missing optional field turns a cosmetic
  /// server change into a broken screen.
  static AccountDevice fromJson(Map<String, Object?> json) => AccountDevice(
    id: _string(json['id']) ?? '',
    name: _string(json['name']) ?? 'Unknown device',
    platform: _string(json['platform']) ?? 'unknown',
    appVersion: _string(json['app_version']),
    lastSeenAt: _dateTime(json['last_seen_at']),
    revokedAt: _dateTime(json['revoked_at']),
  );

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static DateTime? _dateTime(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
