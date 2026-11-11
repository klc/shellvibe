
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:cryptography/cryptography.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:shellvibe/features/vault/presentation/dialogs/vault_unlock_dialog.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/vault_notifier.dart';
import 'package:shellvibe/app/widgets/shellvibe_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fastEngine = EncryptionEngine(
    kdf: Argon2id(parallelism: 1, memory: 8, iterations: 1, hashLength: 32),
  );

  late AppDatabase db;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        encryptionEngineProvider.overrideWithValue(fastEngine),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
  }

  Widget createWidgetUnderTest(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.light(),
          brightness: Brightness.light,
        ),
        child: const MaterialApp(home: VaultUnlockDialog()),
      ),
    );
  }

  group('VaultUnlockDialog Widget Tests', () {
    testWidgets('Renders password field and unlock button', (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(createWidgetUnderTest(container));
      await tester.pump();

      expect(find.text('Unlock Vault'), findsOneWidget);
      expect(find.byType(ShadInput), findsOneWidget);
      expect(find.widgetWithText(ShellVibeButton, 'Unlock'), findsOneWidget);
    });

    testWidgets('Displays error feedback when wrong password is submitted', (
      tester,
    ) async {
      final container = createContainer();
      addTearDown(container.dispose);

      // Setup vault with password
      final notifier = container.read(vaultProvider.notifier);
      await notifier.setup('CorrectPassword123');
      notifier.lock();

      await tester.pumpWidget(createWidgetUnderTest(container));
      await tester.pump();

      // Enter wrong password
      await tester.enterText(find.byType(ShadInput), 'WrongPassword');
      await tester.tap(find.widgetWithText(ShellVibeButton, 'Unlock'));
      await tester.idle();
      await tester.pump();

      expect(find.text('Incorrect password'), findsOneWidget);
      expect(find.text('Failed attempts: 1'), findsOneWidget);
    });

    testWidgets('Displays lockout UI when max failed attempts reached', (
      tester,
    ) async {
      final container = createContainer();
      addTearDown(container.dispose);

      final notifier = container.read(vaultProvider.notifier);
      await notifier.setup('CorrectPassword123');
      notifier.lock();

      // 5 failed unlock attempts
      for (int i = 0; i < 5; i++) {
        await notifier.unlock('WrongPassword');
      }

      await tester.pumpWidget(createWidgetUnderTest(container));
      await tester.pump();

      expect(find.text('Too Many Attempts'), findsOneWidget);
      expect(find.textContaining('Please wait'), findsOneWidget);

      // Unlock button should be disabled when locked out
      final button = tester.widget<ShellVibeButton>(
        find.widgetWithText(ShellVibeButton, 'Unlock'),
      );
      expect(button.onPressed, isNull);

      // Advance time past lockout duration so periodic timer cancels before test teardown
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('a forgotten password can be reset, once typed out', (
      tester,
    ) async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(vaultProvider.notifier);
      await tester.runAsync(() => notifier.setup('CorrectPassword123'));
      await tester.runAsync(notifier.lock);

      await tester.pumpWidget(createWidgetUnderTest(container));
      await tester.pump();

      await tester.tap(find.byKey(const Key('vault_reset_button')));
      await tester.pumpAndSettle();

      final confirm = find.byKey(const Key('vault_reset_confirm_button'));
      expect(tester.widget<ShellVibeButton>(confirm).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('vault_reset_confirm_field')),
        'RESET',
      );
      await tester.pump();
      expect(tester.widget<ShellVibeButton>(confirm).onPressed, isNotNull);

      await tester.tap(confirm);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(
        container.read(vaultProvider).value!.status,
        VaultStatus.unconfigured,
      );
    });

    testWidgets('a lost key offers a retry and the reset, no password', (tester) async {
      // Encrypted rows, no key: the keychain lost it.
      await tester.runAsync(
        () => db.identitiesDao.insertIdentity(
          IdentitiesCompanion.insert(
            id: 'id-1',
            workspaceId: 'default',
            title: 'prod',
            username: 'root',
            authType: 'password',
            passwordEncrypted: const Value('ciphertext'),
            createdAt: DateTime(2026),
          ),
        ),
      );
      final container = createContainer();
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(vaultProvider.future));

      await tester.pumpWidget(createWidgetUnderTest(container));
      await tester.pump();

      expect(find.text('Vault Key Missing'), findsOneWidget);
      expect(find.byType(ShadInput), findsNothing);
      expect(find.byKey(const Key('vault_retry_key_button')), findsOneWidget);
      expect(find.byKey(const Key('vault_reset_button')), findsOneWidget);
    });

    testWidgets('Try Again recovers once the key can be read', (tester) async {
      await tester.runAsync(
        () => db.identitiesDao.insertIdentity(
          IdentitiesCompanion.insert(
            id: 'id-1',
            workspaceId: 'default',
            title: 'prod',
            username: 'root',
            authType: 'password',
            passwordEncrypted: const Value('ciphertext'),
            createdAt: DateTime(2026),
          ),
        ),
      );
      final container = createContainer();
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(vaultProvider.future));

      await tester.pumpWidget(createWidgetUnderTest(container));
      await tester.pump();
      expect(find.text('Vault Key Missing'), findsOneWidget);

      // A first try while the keychain still answers empty changes nothing.
      await tester.tap(find.byKey(const Key('vault_retry_key_button')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.text('Vault Key Missing'), findsOneWidget);
      expect(
        find.text('The key is still not in the keychain.'),
        findsOneWidget,
      );

      // The keyring is unlocked; the key answers now.
      await tester.runAsync(
        () => container
            .read(secureStorageServiceProvider)
            .saveMasterKey(List.filled(32, 7)),
      );
      await tester.ensureVisible(
        find.byKey(const Key('vault_retry_key_button')),
      );
      await tester.tap(find.byKey(const Key('vault_retry_key_button')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();

      final state = container.read(vaultProvider).value!;
      expect(state.keyLost, isFalse);
      expect(state.status, VaultStatus.unconfigured);
      expect(find.text('Vault Key Missing'), findsNothing);
      expect(
        await tester.runAsync(() => db.identitiesDao.getAllIdentities()),
        hasLength(1),
        reason: 'nothing was reset',
      );
    });
  });
}
