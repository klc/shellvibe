import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/database/daos/hosts_dao.dart';
import 'package:shellvibe/shared/database/daos/identities_dao.dart';

void main() {
  group('HostsDao Unit Tests', () {
    late AppDatabase db;
    late HostsDao hostsDao;
    late IdentitiesDao identitiesDao;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      hostsDao = db.hostsDao;
      identitiesDao = db.identitiesDao;
    });

    tearDown(() async {
      await db.close();
    });

    test('Create, read, update, and delete hosts', () async {
      // 1. Create linked identity with encrypted password/key columns
      await identitiesDao.insertIdentity(
        IdentitiesCompanion.insert(
          id: 'ident-101',
          workspaceId: 'default',
          title: 'Encrypted Identity',
          username: 'admin',
          authType: 'password',
          passwordEncrypted: const Value('ENC_BASE64_PASSWORD_BYTES'),
          privateKeyEncrypted: const Value('ENC_BASE64_KEY_BYTES'),
          createdAt: DateTime.now(),
        ),
      );

      // 2. Insert host linked to identity
      final hostCompanion = HostsCompanion.insert(
        id: 'host-101',
        workspaceId: 'default',
        identityId: const Value('ident-101'),
        label: 'Production DB',
        hostname: '10.0.0.5',
        port: const Value(2222),
        protocol: const Value('ssh'),
        createdAt: DateTime.now(),
      );

      await hostsDao.insertHost(hostCompanion);

      // 3. Read host by ID and workspace
      final fetched = await hostsDao.getHostById('host-101');
      expect(fetched, isNotNull);
      expect(fetched!.label, equals('Production DB'));
      expect(fetched.hostname, equals('10.0.0.5'));
      expect(fetched.port, equals(2222));
      expect(fetched.identityId, equals('ident-101'));

      final workspaceHosts = await hostsDao.getHostsByWorkspace('default');
      expect(workspaceHosts.length, equals(1));
      expect(workspaceHosts.first.id, equals('host-101'));

      // Verify linked identity contains encrypted columns
      final identity = await identitiesDao.getIdentityById(fetched.identityId!);
      expect(identity, isNotNull);
      expect(identity!.passwordEncrypted, equals('ENC_BASE64_PASSWORD_BYTES'));
      expect(identity.privateKeyEncrypted, equals('ENC_BASE64_KEY_BYTES'));

      // 4. Update host
      final updatedHost = fetched.copyWith(
        label: 'Production DB Primary',
        port: 22,
      );
      final updateResult = await hostsDao.updateHostById(
        'host-101',
        updatedHost,
      );
      expect(updateResult, greaterThan(0));

      final reFetched = await hostsDao.getHostById('host-101');
      expect(reFetched!.label, equals('Production DB Primary'));
      expect(reFetched.port, equals(22));

      // 5. Delete host
      final deleteCount = await hostsDao.deleteHost('host-101');
      expect(deleteCount, equals(1));

      final deletedHost = await hostsDao.getHostById('host-101');
      expect(deletedHost, isNull);
    });

    test('HostGroup CRUD operations', () async {
      final groupCompanion = HostGroupsCompanion.insert(
        id: 'group-1',
        workspaceId: 'default',
        name: 'Database Cluster',
      );

      await hostsDao.insertHostGroup(groupCompanion);

      final group = await hostsDao.getHostGroupById('group-1');
      expect(group, isNotNull);
      expect(group!.name, equals('Database Cluster'));

      final allGroups = await hostsDao.getAllHostGroups();
      expect(allGroups.length, equals(1));

      await hostsDao.deleteHostGroup('group-1');
      expect(await hostsDao.getHostGroupById('group-1'), isNull);
    });

    test('assignIdentityToHosts rebinds many hosts in one call', () async {
      await identitiesDao.insertIdentity(
        IdentitiesCompanion.insert(
          id: 'ident-new',
          workspaceId: 'default',
          title: 'Replacement Key',
          username: 'root',
          authType: 'key',
          createdAt: DateTime.now(),
        ),
      );
      for (final id in ['h1', 'h2', 'h3']) {
        await hostsDao.insertHost(
          HostsCompanion.insert(
            id: id,
            workspaceId: 'default',
            label: id,
            hostname: '10.0.0.1',
            createdAt: DateTime.now(),
          ),
        );
      }

      final changed = await hostsDao.assignIdentityToHosts([
        'h1',
        'h3',
      ], 'ident-new');

      expect(changed, equals(2));
      expect((await hostsDao.getHostById('h1'))!.identityId, 'ident-new');
      expect((await hostsDao.getHostById('h2'))!.identityId, isNull);
      expect((await hostsDao.getHostById('h3'))!.identityId, 'ident-new');
    });

    test('assignIdentityToHosts leaves every other column alone', () async {
      await hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'h-keep',
          workspaceId: 'default',
          label: 'Keep me',
          hostname: '10.0.0.9',
          port: const Value(2200),
          protocol: const Value('mosh'),
          colorTag: const Value('#ff0000'),
          createdAt: DateTime.now(),
        ),
      );

      await hostsDao.assignIdentityToHosts(['h-keep'], null);

      final host = await hostsDao.getHostById('h-keep');
      expect(host!.label, 'Keep me');
      expect(host.port, 2200);
      expect(host.protocol, 'mosh');
      expect(host.colorTag, '#ff0000');
    });

    test('assignIdentityToHosts on an empty list is a no-op', () async {
      expect(await hostsDao.assignIdentityToHosts([], 'ident-new'), equals(0));
    });

    test('reassignIdentity moves every host off the old identity', () async {
      for (final id in ['old-ident', 'new-ident']) {
        await identitiesDao.insertIdentity(
          IdentitiesCompanion.insert(
            id: id,
            workspaceId: 'default',
            title: id,
            username: 'root',
            authType: 'key',
            createdAt: DateTime.now(),
          ),
        );
      }
      for (final id in ['a', 'b']) {
        await hostsDao.insertHost(
          HostsCompanion.insert(
            id: id,
            workspaceId: 'default',
            identityId: const Value('old-ident'),
            label: id,
            hostname: '10.0.0.2',
            createdAt: DateTime.now(),
          ),
        );
      }
      await hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'c',
          workspaceId: 'default',
          label: 'c',
          hostname: '10.0.0.3',
          createdAt: DateTime.now(),
        ),
      );

      final changed = await hostsDao.reassignIdentity('old-ident', 'new-ident');

      expect(changed, equals(2));
      expect((await hostsDao.getHostById('a'))!.identityId, 'new-ident');
      expect((await hostsDao.getHostById('b'))!.identityId, 'new-ident');
      expect((await hostsDao.getHostById('c'))!.identityId, isNull);

      // The point of moving first: the delete would otherwise null them out.
      await identitiesDao.deleteIdentity('old-ident');
      expect((await hostsDao.getHostById('a'))!.identityId, 'new-ident');
    });

    test('deleting an identity detaches the hosts that used it', () async {
      await identitiesDao.insertIdentity(
        IdentitiesCompanion.insert(
          id: 'doomed',
          workspaceId: 'default',
          title: 'Doomed',
          username: 'root',
          authType: 'key',
          createdAt: DateTime.now(),
        ),
      );
      await hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'orphan',
          workspaceId: 'default',
          identityId: const Value('doomed'),
          label: 'orphan',
          hostname: '10.0.0.4',
          createdAt: DateTime.now(),
        ),
      );

      await identitiesDao.deleteIdentity('doomed');

      // ON DELETE SET NULL: the binding is gone and nothing records what it was.
      expect((await hostsDao.getHostById('orphan'))!.identityId, isNull);
    });
  });
}
