import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/features/settings/presentation/widgets/vault_master_password_section.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/vault_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        encryptionEngineProvider.overrideWithValue(
          EncryptionEngine(
            kdf: Argon2id(
              parallelism: 1,
              memory: 8,
              iterations: 1,
              hashLength: 32,
            ),
          ),
        ),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.runAsync(() => container.read(vaultProvider.future));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ShadApp(
          home: Scaffold(body: VaultMasterPasswordSection()),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> submit(
    WidgetTester tester,
    String password,
    String repeat,
  ) async {
    await tester.enterText(
      find.byKey(const Key('vault_master_password_field')),
      password,
    );
    await tester.enterText(
      find.byKey(const Key('vault_master_password_confirm_field')),
      repeat,
    );
    await tester.tap(find.byKey(const Key('set_master_password_button')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  testWidgets('a mistyped repeat does not set the password', (tester) async {
    await pumpSection(tester);

    await submit(tester, 'correct horse battery', 'correct horse batery');

    expect(find.text('The two passwords do not match.'), findsOneWidget);
    expect(
      container.read(vaultProvider).value!.status,
      VaultStatus.unconfigured,
    );
  });

  testWidgets('a matching repeat sets it', (tester) async {
    await pumpSection(tester);

    await submit(tester, 'correct horse battery', 'correct horse battery');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(container.read(vaultProvider).value!.status, VaultStatus.unlocked);
  });
}
