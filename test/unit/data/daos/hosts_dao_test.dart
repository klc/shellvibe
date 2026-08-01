import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/database/daos/hosts_dao.dart';
import 'package:terly2/shared/database/daos/identities_dao.dart';

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
      final updateResult = await hostsDao.updateHost(updatedHost);
      expect(updateResult, isTrue);

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
  });
}
