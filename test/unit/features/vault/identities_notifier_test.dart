import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/features/vault/presentation/notifiers/identities_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;

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
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('IdentitiesNotifier Unit Tests', () {
    test('Initial state is empty list', () async {
      final state = await container.read(identitiesProvider.future);
      expect(state, isEmpty);
    });

    test('addIdentity creates encrypted identity and updates state', () async {
      final notifier = container.read(identitiesProvider.notifier);

      await notifier.addIdentity(
        workspaceId: 'default',
        title: 'Production Server Key',
        username: 'ubuntu',
        authType: 'password',
        password: 'SecretPassword123',
      );

      final state = await container.read(identitiesProvider.future);
      expect(state.length, equals(1));
      expect(state.first.title, equals('Production Server Key'));
      expect(state.first.username, equals('ubuntu'));
      expect(state.first.password, isNull);

      final decrypted = await notifier.getDecryptedIdentity(state.first.id);
      expect(decrypted, isNotNull);
      expect(decrypted!.password, equals('SecretPassword123'));
    });

    test('updateIdentity modifies existing record', () async {
      final notifier = container.read(identitiesProvider.notifier);

      await notifier.addIdentity(
        workspaceId: 'default',
        title: 'Old Title',
        username: 'root',
        authType: 'password',
        password: 'Pass1',
      );

      var state = await container.read(identitiesProvider.future);
      final id = state.first.id;

      await notifier.updateIdentity(
        id: id,
        workspaceId: 'default',
        title: 'New Title',
        username: 'admin',
        authType: 'password',
        password: 'Pass2',
      );

      state = await container.read(identitiesProvider.future);
      expect(state.length, equals(1));
      expect(state.first.title, equals('New Title'));
      expect(state.first.username, equals('admin'));
      expect(state.first.password, isNull);

      final decrypted = await notifier.getDecryptedIdentity(id);
      expect(decrypted, isNotNull);
      expect(decrypted!.password, equals('Pass2'));
    });

    test('deleteIdentity removes record from state', () async {
      final notifier = container.read(identitiesProvider.notifier);

      await notifier.addIdentity(
        workspaceId: 'default',
        title: 'Key To Delete',
        username: 'user',
        authType: 'key',
        privateKey: 'PEM_DATA',
      );

      var state = await container.read(identitiesProvider.future);
      expect(state.length, equals(1));
      final id = state.first.id;

      await notifier.deleteIdentity(id);

      state = await container.read(identitiesProvider.future);
      expect(state, isEmpty);
    });

    test(
      'failed identity update preserves the previously loaded list',
      () async {
        final notifier = container.read(identitiesProvider.notifier);

        await notifier.addIdentity(
          workspaceId: 'default',
          title: 'Stable Identity',
          username: 'stable-user',
          authType: 'password',
          password: 'StablePassword123',
        );
        final previousIdentities = container
            .read(identitiesProvider)
            .requireValue;

        await expectLater(
          notifier.updateIdentity(
            id: 'missing-identity',
            workspaceId: 'default',
            title: 'Missing Identity',
            username: 'missing-user',
            authType: 'password',
            password: 'MissingPassword123',
          ),
          throwsA(isA<StateError>()),
        );

        final currentState = container.read(identitiesProvider);
        expect(currentState.hasError, isFalse);
        expect(currentState.requireValue, same(previousIdentities));
      },
    );

    test(
      'findUndecryptableIds flags a secret written under another key',
      () async {
        final notifier = container.read(identitiesProvider.notifier);
        await notifier.addIdentity(
          workspaceId: 'default',
          title: 'Healthy',
          username: 'root',
          authType: 'key',
          privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----',
        );
        // A row whose ciphertext this install's DEK cannot open — what a restored
        // backup or a lost keychain entry leaves behind.
        await db.identitiesDao.insertIdentity(
          IdentitiesCompanion.insert(
            id: 'broken',
            workspaceId: 'default',
            title: 'Broken',
            username: 'root',
            authType: 'key',
            privateKeyEncrypted: const Value('not-decryptable-with-this-key'),
            createdAt: DateTime.now(),
          ),
        );
        container.invalidate(identitiesProvider);
        await container.read(identitiesProvider.future);

        final broken = await container
            .read(identitiesProvider.notifier)
            .findUndecryptableIds();

        expect(broken, equals({'broken'}));
      },
    );

    test('repairing an identity keeps its id and clears the flag', () async {
      await db.identitiesDao.insertIdentity(
        IdentitiesCompanion.insert(
          id: 'needs-repair',
          workspaceId: 'default',
          title: 'Imported Key',
          username: 'root',
          authType: 'key',
          privateKeyEncrypted: const Value('unreadable'),
          createdAt: DateTime.now(),
        ),
      );
      // A host bound to it: the whole point of repairing in place is that this
      // binding survives.
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'host-1',
          workspaceId: 'default',
          identityId: const Value('needs-repair'),
          label: 'Prod',
          hostname: '10.0.0.1',
          createdAt: DateTime.now(),
        ),
      );
      final notifier = container.read(identitiesProvider.notifier);
      await container.read(identitiesProvider.future);
      expect(await notifier.findUndecryptableIds(), equals({'needs-repair'}));

      await notifier.updateIdentity(
        id: 'needs-repair',
        workspaceId: 'default',
        title: 'Imported Key',
        username: 'root',
        authType: 'key',
        privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----replacement',
      );

      expect(await notifier.findUndecryptableIds(), isEmpty);
      expect(
        (await db.hostsDao.getHostById('host-1'))!.identityId,
        equals('needs-repair'),
      );
      final repaired = await notifier.getDecryptedIdentity('needs-repair');
      expect(
        repaired!.privateKey,
        equals('-----BEGIN OPENSSH PRIVATE KEY-----replacement'),
      );
    });
  });
}
