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

    testWidgets('shows the free plan as not including cloud backup', (
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
      expect(
        find.textContaining('not included in this plan'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('account_sign_out_button')), findsOneWidget);
    });

    testWidgets('shows the real limits on a paid plan', (tester) async {
      await pumpSignedIn(
        tester,
        billing: EntitlementState(
          entitlement: _proEntitlement,
          source: EntitlementSource.server,
        ),
      );

      expect(find.text('Pro plan'), findsOneWidget);
      expect(find.textContaining('5 MB per backup'), findsOneWidget);
      expect(find.textContaining('10 revisions'), findsOneWidget);
    });

    testWidgets('marks a grace period as payment overdue', (tester) async {
      await pumpSignedIn(
        tester,
        billing: EntitlementState(
          entitlement: Entitlement.fromJson(const {
            'plan': 'pro',
            'status': 'grace',
            'capabilities': ['cloud_backup'],
            'limits': {
              'max_backup_size_bytes': 5242880,
              'max_backup_revisions': 10,
            },
          }),
          source: EntitlementSource.server,
        ),
      );

      expect(find.textContaining('payment overdue'), findsOneWidget);
      expect(
        find.textContaining('Cloud backup is included'),
        findsOneWidget,
        reason: 'Grace still grants access.',
      );
    });

    testWidgets(
      'blames the network, not the subscription, when the check failed',
      (tester) async {
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
              '"You need Pro" and "we could not check" ask the user to do '
              'different things.',
        );
        expect(find.text('Free plan'), findsNothing);
      },
    );
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

final _proEntitlement = Entitlement.fromJson(const {
  'plan': 'pro',
  'status': 'active',
  'capabilities': ['local_device_link', 'cloud_backup'],
  'limits': {'max_backup_size_bytes': 5242880, 'max_backup_revisions': 10},
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

  @override
  Future<EntitlementState> build() async => _state;
}
