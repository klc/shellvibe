import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../domain/account_session.dart';
import 'device_descriptor.dart';

/// A completed sign-in, carrying the one and only copy of the
/// bearer token before it is handed to storage.
@immutable
final class AuthResult {
  final String token;
  final AccountSession session;

  const AuthResult({required this.token, required this.session});
}

/// A browser sign-in waiting for the person to approve it in the web panel.
@immutable
final class BrowserSignIn {
  final String id;

  /// Proves to the server that the poll comes from the app that opened the
  /// request. Never shown, never put in a URL.
  final String secret;

  /// Shown in the app and on the approval page, so the person can tell this
  /// request from one somebody else sent them a link to.
  final String userCode;

  /// The approval page, on the panel's host.
  final String verificationUrl;

  final Duration interval;

  const BrowserSignIn({
    required this.id,
    required this.secret,
    required this.userCode,
    required this.verificationUrl,
    this.interval = const Duration(seconds: 2),
  });

  factory BrowserSignIn.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final secret = json['secret'];
    final userCode = json['user_code'];
    final url = json['verification_url'];

    if (id is! String ||
        id.isEmpty ||
        secret is! String ||
        secret.isEmpty ||
        userCode is! String ||
        url is! String) {
      throw const AccountApiException(
        'The sign-in request came back without its id, secret, code or URL.',
      );
    }

    final interval = json['interval'];

    return BrowserSignIn(
      id: id,
      secret: secret,
      userCode: userCode,
      verificationUrl: url,
      interval: Duration(
        seconds: interval is int && interval > 0 ? interval : 2,
      ),
    );
  }
}

/// The `/auth`, `/me`, `/devices` and `/account` part of the v1 API.
final class AccountApi {
  final ApiClient client;

  const AccountApi({required this.client});

  /// Opens a browser sign-in. The person approves it in the web panel, where
  /// they sign in or create an account however they like, and
  /// [pollBrowserSignIn] collects the token.
  ///
  /// Sending [knownDeviceId] matters: without it the server opens a *new*
  /// device record on every sign-in, so the same laptop accumulates entries in
  /// the account's device list and in relay presence.
  Future<BrowserSignIn> startBrowserSignIn({
    String? knownDeviceId,
    DeviceDescriptor? device,
  }) async {
    final descriptor = device ?? DeviceDescriptor.current();

    final response = await client.post(
      '/auth/app-sign-in',
      authenticated: false,
      body: {
        'device_name': descriptor.name,
        'platform': descriptor.platform,
        'app_version': descriptor.appVersion,
        if (knownDeviceId != null && knownDeviceId.isNotEmpty)
          'device_id': knownDeviceId,
      },
    );

    return BrowserSignIn.fromJson(response.dataMap);
  }

  /// The session once [request] is approved, null while it is still waiting.
  ///
  /// Throws [ApiException] `sign_in_denied` when it was denied in the browser
  /// and `sign_in_expired` when it ran out or was already collected.
  Future<AuthResult?> pollBrowserSignIn(BrowserSignIn request) async {
    final response = await client.post(
      '/auth/app-sign-in/${request.id}/token',
      authenticated: false,
      body: {'secret': request.secret},
    );

    final data = response.dataMap;
    if (data['status'] != 'approved') return null;

    return _authResult(data);
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

    return response.dataList
        .map(AccountDevice.fromJson)
        .toList(growable: false);
  }

  /// Revokes another device's access.
  Future<void> revokeDevice(String deviceId) =>
      client.delete('/devices/$deviceId');

  /// Permanently erases the account, with its devices, backups and sync
  /// history.
  ///
  /// The server asks for the current [password] on top of the bearer token, so
  /// a leaked token alone cannot destroy an account. It refuses with
  /// `422 invalid_credentials` on a wrong password and `409
  /// account_owns_shared_team` while a team the user owns has other members.
  Future<void> deleteAccount({required String password}) =>
      client.delete('/account', body: {'password': password});

  AuthResult _authResult(Map<String, Object?> data) {
    final token = data['token'];
    if (token is! String || token.isEmpty) {
      throw const AccountApiException(
        'The server accepted the sign-in but returned no token.',
      );
    }

    return AuthResult(token: token, session: _sessionFrom(data));
  }

  AccountSession _sessionFrom(Map<String, Object?> data) {
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
      email: email is String ? email : '',
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
