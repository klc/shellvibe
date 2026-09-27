import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_client.dart';
import 'package:shellvibe/features/account/domain/account_session.dart';
import 'package:shellvibe/features/account/presentation/notifiers/account_notifier.dart';
import 'package:shellvibe/features/billing/domain/entitlement.dart';
import 'package:shellvibe/features/billing/presentation/notifiers/entitlement_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

import 'fake_sync_server.dart';
import 'fast_crypto.dart';

/// A container for a device signed in to an account that [server] serves.
///
/// Everything else is the app's own wiring: secure storage (mocked by the
/// caller with `FlutterSecureStorage.setMockInitialValues`), the vault, the
/// sync and backup services and their stores. Only the KDF is cheapened; see
/// [fastEncryptionEngine].
ProviderContainer signedInContainer({
  required AppDatabase db,
  required FakeSyncServer server,
  String deviceId = 'device-a',
}) => ProviderContainer(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    encryptionEngineProvider.overrideWithValue(fastEncryptionEngine()),
    accountProvider.overrideWith(
      () => _SignedInAccount(
        ApiClient(transport: server, tokenProvider: () async => 'test-token'),
        deviceId,
      ),
    ),
    entitlementProvider.overrideWith(_FreePlan.new),
  ],
);

/// Polls [condition] until it holds.
///
/// The notifiers under test start work they do not return — a join, a
/// scheduled backup — and it finishes on real file and crypto I/O, not on a
/// microtask a `pumpEventQueue` would reach.
Future<void> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(reason ?? 'condition not reached within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

final class _SignedInAccount extends AccountNotifier {
  _SignedInAccount(this._client, this._deviceId);

  final ApiClient _client;
  final String _deviceId;

  @override
  Future<AccountState> build() async => AccountState(
    status: AccountStatus.signedIn,
    session: AccountSession(
      userId: 'user-1',
      deviceId: _deviceId,
      email: 'user@shellvibe.dev',
      name: 'User',
    ),
  );

  @override
  ApiClient get apiClient => _client;
}

final class _FreePlan extends EntitlementNotifier {
  @override
  Future<EntitlementState> build() async => const EntitlementState(
    entitlement: Entitlement.free,
    source: EntitlementSource.server,
  );
}
