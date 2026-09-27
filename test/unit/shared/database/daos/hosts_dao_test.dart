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
