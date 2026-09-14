import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:cryptography/cryptography.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/features/vault/presentation/screens/vault_screen.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fastEngine = EncryptionEngine(
    kdf: Argon2id(parallelism: 1, memory: 8, iterations: 1, hashLength: 32),
  );

  late AppDatabase db;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'default',
        name: 'Default Workspace',
        createdAt: DateTime.now(),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Widget createWidgetUnderTest() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        encryptionEngineProvider.overrideWithValue(fastEngine),
      ],
      child: ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.light(),
          brightness: Brightness.light,
        ),
        // ShadToaster has to be in the tree: several vault actions report
        // their result with a toast.
        child: MaterialApp(
          builder: (context, child) => ShadToaster(child: child!),
          home: const VaultScreen(),
        ),
      ),
    );
  }

  group('VaultScreen Widget Tests', () {
    testWidgets('Renders AppBar title and add button', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Identity Vault'), findsOneWidget);
      expect(find.byKey(const Key('add_identity_button')), findsOneWidget);
      expect(find.byKey(const Key('vault_search_input')), findsOneWidget);
    });

    testWidgets('Opens IdentityFormDialog on add button tap', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('add_identity_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Add New Identity'), findsOneWidget);
      expect(find.byKey(const Key('identity_title_input')), findsOneWidget);
      expect(find.byKey(const Key('identity_username_input')), findsOneWidget);
      expect(find.byKey(const Key('identity_save_button')), findsOneWidget);
    });

    testWidgets('Identity row reads in full at a phone width', (tester) async {
      await db.identitiesDao.insertIdentity(
        IdentitiesCompanion.insert(
          id: 'identity-1',
          workspaceId: 'default',
          title: 'Production Server Key',
          username: 'root',
          authType: 'key',
          createdAt: DateTime.now(),
        ),
      );

      tester.view.physicalSize = const Size(411, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The four controls take more width than three text columns can spare
      // on a phone, so the row stacks instead: title on its own line, the
      // columns folded into one metadata line under it.
      expect(
        find.textContaining(
          'private key · root · unused',
          findRichText: true,
        ),
        findsOneWidget,
      );
      // The title is the regression: as a table column it ellipsised after
      // about seven characters.
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Production Server Key'))
            .didExceedMaxLines,
        isFalse,
      );
      expect(
        find.byKey(const Key('copy_identity_button_identity-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('delete_identity_button_identity-1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('A wide window keeps the table columns', (tester) async {
      await db.identitiesDao.insertIdentity(
        IdentitiesCompanion.insert(
          id: 'identity-1',
          workspaceId: 'default',
          title: 'Production Server Key',
          username: 'root',
          authType: 'key',
          createdAt: DateTime.now(),
        ),
      );

      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Separate columns, not the stacked metadata line.
      expect(find.text('private key'), findsOneWidget);
      expect(find.text('root'), findsOneWidget);
      expect(find.text('unused'), findsOneWidget);
      expect(
        find.textContaining(
          'private key · root · unused',
          findRichText: true,
        ),
        findsNothing,
      );
    });

    testWidgets('A password identity is not labelled "no passphrase"', (
      tester,
    ) async {
      await db.identitiesDao.insertIdentity(
        IdentitiesCompanion.insert(
          id: 'pw-1',
          workspaceId: 'default',
          title: 'Bastion login',
          username: 'ubuntu',
          authType: 'password',
          createdAt: DateTime.now(),
        ),
      );

      tester.view.physicalSize = const Size(411, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Passphrases belong to keys. On a password identity the line read as
      // "no password stored", right after one was.
      expect(
        find.textContaining('no passphrase', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('password · ubuntu · unused', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('An unreadable identity offers repair instead of a dead end', (
      tester,
    ) async {
      // Ciphertext this install's vault key cannot open — what a restored
      // backup or a lost keychain entry leaves behind.
      await db.identitiesDao.insertIdentity(
        IdentitiesCompanion.insert(
          id: 'broken-1',
          workspaceId: 'default',
          title: 'Imported Key',
          username: 'root',
          authType: 'key',
          privateKeyEncrypted: const Value('unreadable-ciphertext'),
          createdAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('secret unreadable'), findsOneWidget);

      await tester.tap(find.byKey(const Key('edit_identity_button_broken-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Repair Identity'), findsOneWidget);
      expect(find.text('Replace secret'), findsOneWidget);
      // The notice has to say the old secret is unrecoverable, otherwise
      // deleting the identity still looks like the reasonable next move.
      expect(
        find.textContaining('cannot be read or recovered'),
        findsOneWidget,
      );
      // Editing this identity, not creating a new one: its title comes along.
      expect(find.byKey(const Key('identity_title_input')), findsOneWidget);
      expect(find.text('Imported Key'), findsWidgets);
    });

    testWidgets('Deleting an identity warns about the hosts bound to it', (
      tester,
    ) async {
      await db.identitiesDao.insertIdentity(
        IdentitiesCompanion.insert(
          id: 'in-use',
          workspaceId: 'default',
          title: 'Shared Key',
          username: 'root',
          authType: 'key',
          createdAt: DateTime.now(),
        ),
      );
      for (final id in ['h1', 'h2']) {
        await db.hostsDao.insertHost(
          HostsCompanion.insert(
            id: id,
            workspaceId: 'default',
            identityId: const Value('in-use'),
            label: id,
            hostname: '10.0.0.1',
            createdAt: DateTime.now(),
          ),
        );
      }

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byKey(const Key('delete_identity_button_in-use')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('2 hosts use this identity'), findsOneWidget);
    });

    testWidgets('Assign-to-hosts lists the workspace hosts', (tester) async {
      await db.identitiesDao.insertIdentity(
        IdentitiesCompanion.insert(
          id: 'fresh-key',
          workspaceId: 'default',
          title: 'Replacement Key',
          username: 'root',
          authType: 'key',
          createdAt: DateTime.now(),
        ),
      );
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'orphan-host',
          workspaceId: 'default',
          label: 'Orphaned Host',
          hostname: '10.0.0.7',
          createdAt: DateTime.now(),
        ),
      );

      // The dialog is 460x~400: the default 800x600 test surface puts its
      // controls off-screen, where taps cannot reach them.
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byKey(const Key('assign_hosts_button_fresh-key')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Assign hosts'), findsOneWidget);
      expect(find.text('Orphaned Host'), findsOneWidget);

      await tester.tap(find.text('Orphaned Host'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('assign_hosts_save_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        (await db.hostsDao.getHostById('orphan-host'))!.identityId,
        equals('fresh-key'),
      );
    });
  });
}
