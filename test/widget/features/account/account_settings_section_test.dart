import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/features/account/domain/account_session.dart';
import 'package:shellvibe/features/account/presentation/notifiers/account_notifier.dart';
import 'package:shellvibe/features/account/presentation/widgets/account_settings_section.dart';
import 'package:shellvibe/features/billing/domain/entitlement.dart';
import 'package:shellvibe/features/billing/presentation/notifiers/entitlement_notifier.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

import '../../../support/fake_api_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: AccountSettingsSection()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('signed out', () {
    testWidgets('offers sign-in without demanding it', (tester) async {
      await pumpSection(tester);

      expect(find.byKey(const Key('account_submit_button')), findsOneWidget);
      expect(
        find.textContaining('only needed for cloud backup'),
        findsOneWidget,
        reason:
            'The copy must not read as a requirement; the app works signed '
            'out.',
      );
    });

    testWidgets('switches between sign-in and create-account', (tester) async {
      await pumpSection(tester);

      expect(find.text('Sign In'), findsOneWidget);
      expect(find.byKey(const Key('account_field_name')), findsNothing);

      await tester.tap(find.byKey(const Key('account_toggle_mode_button')));
      await tester.pumpAndSettle();

      expect(find.text('Create Account'), findsOneWidget);
      expect(
        find.byKey(const Key('account_field_name')),
        findsOneWidget,
        reason: 'Registration needs a name; sign-in does not.',
      );
    });

    testWidgets('prefills the last email that signed in here', (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        SecureStorageKeys.accountEmail: 'returning@shellvibe.dev',
      });

      await pumpSection(tester);

      expect(find.text('returning@shellvibe.dev'), findsOneWidget);
    });

    testWidgets('does not show plan or device controls', (tester) async {
      await pumpSection(tester);

      expect(find.byKey(const Key('account_devices_button')), findsNothing);
      expect(find.byKey(const Key('account_sign_out_button')), findsNothing);
      expect(find.textContaining('plan'), findsNothing);
    });
  });

  group('session expired', () {
    testWidgets('says the server ended the session', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountProvider.overrideWith(
              () => _StubAccountNotifier(
                const AccountState(
                  status: AccountStatus.sessionExpired,
                  lastEmail: 'user@shellvibe.dev',
                ),
              ),
            ),
          ],
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(child: AccountSettingsSection()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('signed out by the server'),
        findsOneWidget,
        reason:
            'An unexplained empty form reads as the app losing the account.',
      );
      expect(find.byKey(const Key('account_submit_button')), findsOneWidget);
    });
  });

  group('signed in', () {
    Future<void> pumpSignedIn(
      WidgetTester tester, {
      required EntitlementState billing,
    }) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountProvider.overrideWith(
              () => _StubAccountNotifier(_signedInState),
            ),
            entitlementProvider.overrideWith(
              () => _StubEntitlementNotifier(billing),
            ),
          ],
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(child: AccountSettingsSection()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the free plan with cloud backup included', (
      tester,
    ) async {
      await pumpSignedIn(
        tester,
        billing: const EntitlementState(
          entitlement: Entitlement.free,
          source: EntitlementSource.server,
        ),
      );

      expect(find.text('Free plan'), findsOneWidget);
      expect(find.textContaining('are included'), findsOneWidget);
      expect(find.textContaining('5 MB per backup'), findsOneWidget);
      expect(find.byKey(const Key('account_sign_out_button')), findsOneWidget);
    });

    testWidgets('shows the account\'s own limits on a team tier', (
      tester,
    ) async {
      await pumpSignedIn(
        tester,
        billing: EntitlementState(
          entitlement: _teamEntitlement,
          source: EntitlementSource.server,
        ),
      );

      expect(find.text('Team plan'), findsOneWidget);
      expect(find.textContaining('15 MB per backup'), findsOneWidget);
      expect(find.textContaining('30 revisions'), findsOneWidget);
    });

    testWidgets('names a legacy pro grant as free rather than as a tier', (
      tester,
    ) async {
      // Accounts granted `pro` before every feature went free still report it.
      // Calling it a plan of its own would imply they are getting something
      // the free plan does not carry, and they are not.
      await pumpSignedIn(
        tester,
        billing: EntitlementState(
          entitlement: Entitlement.fromJson(const {
            'plan': 'pro',
            'status': 'active',
            'capabilities': ['local_device_link', 'cloud_backup'],
            'limits': {
              'max_backup_size_bytes': 5242880,
              'max_backup_revisions': 10,
            },
          }),
          source: EntitlementSource.server,
        ),
      );

      expect(find.text('Free plan'), findsOneWidget);
      expect(find.text('Pro plan'), findsNothing);
    });

    testWidgets('says the limits are standard ones when the check failed', (
      tester,
    ) async {
      await pumpSignedIn(
        tester,
        billing: const EntitlementState(
          entitlement: Entitlement.free,
          source: EntitlementSource.unavailable,
        ),
      );

      expect(
        find.textContaining('could not be checked'),
        findsOneWidget,
        reason:
            'Nothing is locked by this, but the numbers shown are this '
            'build\'s defaults rather than the account\'s.',
      );
      expect(
        find.text('Free plan'),
        findsOneWidget,
        reason: 'The plan row stays; only the numbers are in doubt.',
      );
    });

    testWidgets('offers account deletion inside the app', (tester) async {
      await pumpSignedIn(
        tester,
        billing: const EntitlementState(
          entitlement: Entitlement.free,
          source: EntitlementSource.server,
        ),
      );

      expect(
        find.byKey(const Key('account_delete_button')),
        findsOneWidget,
        reason:
            'App Store 5.1.1(v) and Play require deletion to be reachable '
            'from inside an app that can create an account.',
      );
      expect(find.textContaining('web panel'), findsNothing);
    });
  });

  group('account deletion', () {
    late FakeApiTransport transport;
    late _StubEntitlementNotifier entitlement;

    Future<void> openDeleteDialog(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      FlutterSecureStorage.setMockInitialValues({
        SecureStorageKeys.accountToken: 'test-token',
        SecureStorageKeys.accountUserId: '01USERULID0000000000000000',
        SecureStorageKeys.accountDeviceId: '01DEVICEULID00000000000000',
        SecureStorageKeys.accountEmail: 'user@shellvibe.dev',
      });
      transport = FakeApiTransport();
      entitlement = _StubEntitlementNotifier(
        const EntitlementState(
          entitlement: Entitlement.free,
          source: EntitlementSource.server,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountApiTransportProvider.overrideWithValue(transport),
            entitlementProvider.overrideWith(() => entitlement),
          ],
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(child: AccountSettingsSection()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('account_delete_button')));
      await tester.pumpAndSettle();
    }

    Future<void> confirmWith(WidgetTester tester, String password) async {
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('account_delete_password')),
          matching: find.byType(EditableText),
        ),
        password,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('account_delete_confirm')));
      await tester.pumpAndSettle();
    }

    testWidgets('says what goes and what stays, and wants the password', (
      tester,
    ) async {
      await openDeleteDialog(tester);

      final dialog = find.byKey(const Key('account_delete_dialog'));
      Finder inDialog(String text) =>
          find.descendant(of: dialog, matching: find.textContaining(text));

      expect(dialog, findsOneWidget);
      expect(inDialog('user@shellvibe.dev'), findsOneWidget);
      expect(inDialog('cloud backups'), findsOneWidget);
      expect(inDialog('sync history'), findsOneWidget);
      expect(inDialog('cannot be undone'), findsOneWidget);
      expect(inDialog('are not touched'), findsOneWidget);

      await tester.tap(find.byKey(const Key('account_delete_confirm')));
      await tester.pumpAndSettle();

      expect(
        transport.sent,
        isEmpty,
        reason: 'The server refuses a delete without the password.',
      );
    });

    testWidgets('a wrong password is answered in place; the right one '
        'deletes and signs out', (tester) async {
      await openDeleteDialog(tester);
      transport
        ..enqueue(
          status: 422,
          body: {
            'code': 'invalid_credentials',
            'message': 'The password does not match this account.',
            'details': <String, Object?>{},
          },
        )
        ..enqueue(
          body: {
            'data': {'deleted': true},
          },
        );

      await confirmWith(tester, 'wrong');

      expect(
        find.text('That password does not match this account.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('account_delete_dialog')), findsOneWidget);
      expect(
        find.byKey(const Key('account_delete_web_panel')),
        findsNothing,
        reason: 'The API answered; the web panel would refuse the same way.',
      );
      expect(entitlement.cacheCleared, isFalse);

      await confirmWith(tester, 'right');

      expect(transport.lastRequest!.method, 'DELETE');
      expect(transport.lastBody, {'password': 'right'});
      expect(find.byKey(const Key('account_delete_dialog')), findsNothing);
      expect(find.byKey(const Key('account_submit_button')), findsOneWidget);
      expect(
        entitlement.cacheCleared,
        isTrue,
        reason: 'Deletion forgets the account the way sign-out does.',
      );
    });

    testWidgets('a team owner is told why the server refused', (tester) async {
      await openDeleteDialog(tester);
      transport.enqueue(
        status: 409,
        body: {
          'code': 'account_owns_shared_team',
          'message': 'Transfer or empty every team you own first.',
          'details': {
            'team_ids': ['01TEAM'],
          },
        },
      );

      await confirmWith(tester, 'right');

      expect(find.textContaining('Hand the team over'), findsOneWidget);
      expect(find.byKey(const Key('account_sign_out_button')), findsOneWidget);
    });

    testWidgets('a throttled attempt says when to retry', (tester) async {
      await openDeleteDialog(tester);
      transport.enqueue(
        status: 429,
        headers: {'Retry-After': '30'},
        body: {
          'code': 'rate_limited',
          'message': 'Too many requests.',
          'details': <String, Object?>{},
        },
      );

      await confirmWith(tester, 'right');

      expect(find.textContaining('Try again in 30 seconds'), findsOneWidget);
    });

    testWidgets('offers the web panel only when the API cannot be reached', (
      tester,
    ) async {
      await openDeleteDialog(tester);
      transport.enqueueTransportFailure();

      await confirmWith(tester, 'right');

      expect(find.textContaining('could not be reached'), findsOneWidget);
      expect(find.byKey(const Key('account_delete_web_panel')), findsOneWidget);
      expect(kAccountDeletionUrl, 'https://shellvibe.dev/panel/danger');
    });
  });
}

const _signedInState = AccountState(
  status: AccountStatus.signedIn,
  session: AccountSession(
    userId: '01USERULID0000000000000000',
    deviceId: '01DEVICEULID00000000000000',
    email: 'user@shellvibe.dev',
    name: 'User',
  ),
  lastEmail: 'user@shellvibe.dev',
);

final _teamEntitlement = Entitlement.fromJson(const {
  'plan': 'team',
  'status': 'active',
  'capabilities': ['local_device_link', 'cloud_backup', 'shared_workspaces'],
  'limits': {'max_backup_size_bytes': 15728640, 'max_backup_revisions': 30},
});

/// Publishes a fixed [AccountState] without touching storage or the network.
final class _StubAccountNotifier extends AccountNotifier {
  _StubAccountNotifier(this._state);

  final AccountState _state;

  @override
  Future<AccountState> build() async => _state;
}

/// Publishes a fixed [EntitlementState].
final class _StubEntitlementNotifier extends EntitlementNotifier {
  _StubEntitlementNotifier(this._state);

  final EntitlementState _state;

  bool cacheCleared = false;

  @override
  Future<EntitlementState> build() async => _state;

  @override
  Future<void> clearCache() async => cacheCleared = true;
}
