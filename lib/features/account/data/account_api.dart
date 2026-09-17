import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../domain/account_session.dart';
import 'device_descriptor.dart';

/// A successful `register` or `login`, carrying the one and only copy of the
/// bearer token before it is handed to storage.
@immutable
final class AuthResult {
  final String token;
  final AccountSession session;

  const AuthResult({required this.token, required this.session});
}

/// The `/auth`, `/me` and `/devices` half of the v1 API.
final class AccountApi {
  final ApiClient client;

  const AccountApi({required this.client});

  /// Creates an account and this device's first session.
  Future<AuthResult> register({
    required String name,
    required String email,
    required String password,
    DeviceDescriptor? device,
  }) async {
    final descriptor = device ?? DeviceDescriptor.current();

    final response = await client.post(
      '/auth/register',
      authenticated: false,
      body: {
        'name': name,
        'email': email,
        'password': password,
        'device_name': descriptor.name,
        'platform': descriptor.platform,
        'app_version': descriptor.appVersion,
      },
    );

    return _authResult(response.dataMap, fallbackEmail: email);
  }

  /// Signs in, reusing [knownDeviceId] when this install already has a device
  /// record.
  ///
  /// Sending the id matters: without it the server opens a *new* device record
  /// on every sign-in, so the same laptop accumulates entries in the account's
  /// device list and in relay presence.
  Future<AuthResult> login({
    required String email,
    required String password,
    String? knownDeviceId,
    DeviceDescriptor? device,
  }) async {
    final descriptor = device ?? DeviceDescriptor.current();

    final response = await client.post(
      '/auth/login',
      authenticated: false,
      body: {
        'email': email,
        'password': password,
        'device_name': descriptor.name,
        'platform': descriptor.platform,
        'app_version': descriptor.appVersion,
        if (knownDeviceId != null && knownDeviceId.isNotEmpty)
          'device_id': knownDeviceId,
      },
    );

    return _authResult(response.dataMap, fallbackEmail: email);
  }

  /// Revokes this device's token.
  Future<void> logout() => client.post('/auth/logout');

  /// Revokes every token on the account, on every device.
  Future<void> logoutAll() => client.post('/auth/logout-all');

  /// Current user and device, for validating a restored session.
  Future<AccountSession> me() async {
    final response = await client.get('/me');

    return _sessionFrom(response.dataMap);
  }

  /// Devices registered to the account.
  Future<List<AccountDevice>> devices() async {
    final response = await client.get('/devices');

    return response.dataList.map(AccountDevice.fromJson).toList(
      growable: false,
    );
  }

  /// Revokes another device's access.
  Future<void> revokeDevice(String deviceId) =>
      client.delete('/devices/$deviceId');

  AuthResult _authResult(
    Map<String, Object?> data, {
    required String fallbackEmail,
  }) {
    final token = data['token'];
    if (token is! String || token.isEmpty) {
      throw const AccountApiException(
        'The server accepted the sign-in but returned no token.',
      );
    }

    return AuthResult(
      token: token,
      session: _sessionFrom(data, fallbackEmail: fallbackEmail),
    );
  }

  AccountSession _sessionFrom(
    Map<String, Object?> data, {
    String? fallbackEmail,
  }) {
    final user = data['user'];
    final device = data['device'];

    if (user is! Map<String, Object?> || device is! Map<String, Object?>) {
      throw const AccountApiException(
        'The account response was missing its user or device member.',
      );
    }

    final userId = user['id'];
    final deviceId = device['id'];

    if (userId is! String ||
        userId.isEmpty ||
        deviceId is! String ||
        deviceId.isEmpty) {
      throw const AccountApiException(
        'The account response carried no usable identifiers.',
      );
    }

    final email = user['email'];

    return AccountSession(
      userId: userId,
      deviceId: deviceId,
      email: email is String && email.isNotEmpty
          ? email
          : (fallbackEmail ?? ''),
      name: user['name'] is String ? user['name']! as String : '',
    );
  }
}

/// A well-formed HTTP response that did not carry the fields the account flow
/// needs.
///
/// Separate from `ApiException`, which describes a request the server
/// *rejected*. This one means the request succeeded and the body still could
/// not be used -- a contract mismatch, not a user-facing error condition.
@immutable
final class AccountApiException implements Exception {
  final String message;

  const AccountApiException(this.message);

  @override
  String toString() => 'AccountApiException: $message';
}
