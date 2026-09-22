import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/api_exception.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../data/account_api.dart';
import '../../data/account_session_store.dart';
import '../../domain/account_session.dart';

part 'account_notifier.g.dart';

/// Where the account session stands.
enum AccountStatus {
  /// No session on this device. The app is fully usable in this state.
  signedOut,

  /// A session is stored and assumed valid.
  signedIn,

  /// A session was stored and the server rejected it. Distinct from
  /// [signedOut] so the UI can say why the user is being asked again instead
  /// of silently showing an empty form.
  sessionExpired,
}

/// Immutable account state.
@immutable
final class AccountState {
  final AccountStatus status;

  /// Present exactly when [status] is [AccountStatus.signedIn].
  final AccountSession? session;

  /// Email to prefill a sign-in form with, when one is known.
  final String? lastEmail;

  const AccountState({
    required this.status,
    this.session,
    this.lastEmail,
  });

  const AccountState.signedOut({this.lastEmail})
    : status = AccountStatus.signedOut,
      session = null;

  bool get isSignedIn => status == AccountStatus.signedIn && session != null;

  AccountState copyWith({
    AccountStatus? status,
    AccountSession? session,
    String? lastEmail,
    bool clearSession = false,
  }) => AccountState(
    status: status ?? this.status,
    session: clearSession ? null : (session ?? this.session),
    lastEmail: lastEmail ?? this.lastEmail,
  );
}

/// Single owner of the account session.
///
/// `keepAlive` because the API client built here holds the `401` callback that
/// writes back into this notifier; a disposed instance would leave a live
/// client pointing at nothing.
///
/// Signing in is never required. Every code path here treats "no account" as a
/// normal resting state, not an error: Local Device Link, SSH, the vault and
/// the terminal all work without one.
@Riverpod(keepAlive: true)
class AccountNotifier extends _$AccountNotifier {
  late final AccountSessionStore _store;
  late final ApiClient _apiClient;
  late final AccountApi _api;

  /// Serializes sign-in and sign-out so two taps cannot interleave a token
  /// write with a token clear.
  Future<void> _queue = Future<void>.value();

  @override
  Future<AccountState> build() async {
    _store = AccountSessionStore(
      storage: ref.watch(secureStorageServiceProvider),
    );

    _apiClient = ApiClient(
      tokenProvider: _store.readToken,
      onUnauthenticated: _onServerRejectedToken,
    );
    ref.onDispose(_apiClient.close);

    _api = AccountApi(client: _apiClient);

    final stored = await _store.read();
    final lastEmail = await _store.readEmail();

    if (stored == null) {
      return AccountState.signedOut(lastEmail: lastEmail);
    }

    // The stored session is published straight away rather than verified
    // first. `GET /me` would make app start depend on the network for a
    // feature the user may not touch this session; a token the server has
    // revoked surfaces on the first real call, which is where
    // [_onServerRejectedToken] handles it.
    return AccountState(
      status: AccountStatus.signedIn,
      session: stored,
      lastEmail: lastEmail ?? stored.email,
    );
  }

  /// The API client bound to this session. Feature repositories take this.
  ApiClient get apiClient => _apiClient;

  /// Creates an account and signs in.
  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) => _serialize(
    () => _api.register(name: name, email: email, password: password),
  );

  /// Signs in, reusing this install's device record when it has one.
  Future<void> signIn({
    required String email,
    required String password,
  }) => _serialize(
    () async => _api.login(
      email: email,
      password: password,
      knownDeviceId: await _store.readDeviceId(),
    ),
  );

  /// Revokes this device's token and drops the local session.
  ///
  /// The local session is cleared even when the network call fails: the user
  /// asked to sign out, and a token this device can no longer reach is not a
  /// reason to keep acting signed in. The server-side token then expires on
  /// its own, or the user revokes the device from another one.
  Future<void> signOut({bool everywhere = false}) async {
    final previous = await future;

    _queue = _queue.then((_) async {
      state = AsyncValue.data(
        AccountState.signedOut(lastEmail: previous.lastEmail),
      );

      try {
        if (everywhere) {
          await _api.logoutAll();
        } else {
          await _api.logout();
        }
      } on ApiFailure catch (e) {
        if (kDebugMode) debugPrint('Sign-out call failed, ignoring: $e');
      } finally {
        await _store.clearSession();
      }
    });

    return _queue;
  }

  /// Forgets the device identity as well, so the next sign-in registers a new
  /// device record.
  Future<void> forgetThisDevice() async {
    await signOut();
    await _store.clearAll();
  }

  /// Devices on the account. Throws [ApiFailure] on a network or API error.
  Future<List<AccountDevice>> devices() => _api.devices();

  /// Revokes another device.
  Future<void> revokeDevice(String deviceId) => _api.revokeDevice(deviceId);

  /// Re-reads the session from the server, adopting whatever it reports.
  ///
  /// Used after a purchase or when the user opens the account screen.
  Future<void> refresh() async {
    final current = await future;
    if (!current.isSignedIn) return;

    final session = await _api.me();
    state = AsyncValue.data(
      current.copyWith(
        status: AccountStatus.signedIn,
        session: session,
        lastEmail: session.email,
      ),
    );
  }

  Future<void> _serialize(Future<AuthResult> Function() action) {
    _queue = _queue.then((_) async {
      final result = await action();
      await _store.write(token: result.token, session: result.session);

      state = AsyncValue.data(
        AccountState(
          status: AccountStatus.signedIn,
          session: result.session,
          lastEmail: result.session.email,
        ),
      );
    });

    return _queue;
  }

  /// Invoked by [ApiClient] when the server answers `401` to any call.
  Future<void> _onServerRejectedToken() async {
    await _store.clearSession();

    final lastEmail = await _store.readEmail();

    // `state` may still be loading if the very first call raced app start.
    state = AsyncValue.data(
      AccountState(status: AccountStatus.sessionExpired, lastEmail: lastEmail),
    );
  }
}

/// The API client of the current session, for feature repositories.
///
/// Watching this rather than constructing an [ApiClient] per feature keeps one
/// token source and one `401` handler in the app.
@Riverpod(keepAlive: true)
Future<ApiClient> sessionApiClient(Ref ref) async {
  await ref.watch(accountProvider.future);

  return ref.watch(accountProvider.notifier).apiClient;
}
