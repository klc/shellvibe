import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/features/hosts/data/repositories/hosts_repository.dart';
import 'package:terly2/shared/database/app_database.dart';

void main() {
  group('HostsRepository', () {
    late AppDatabase database;
    late HostsRepository repository;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      repository = HostsRepository(hostsDao: database.hostsDao);
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'clears nullable host fields when an existing host is edited',
      () async {
        final group = await repository.saveHostGroup(
          workspaceId: 'workspace-1',
          name: 'Servers',
        );
        await database.identitiesDao.insertIdentity(
          IdentitiesCompanion.insert(
            id: 'identity-1',
            workspaceId: 'workspace-1',
            title: 'Admin',
            username: 'admin',
            authType: 'password',
            createdAt: DateTime.now(),
          ),
        );
        final jumpHost = await repository.saveHost(
          workspaceId: 'workspace-1',
          label: 'Jump host',
          hostname: 'jump.example.com',
        );
        final host = await repository.saveHost(
          workspaceId: 'workspace-1',
          groupId: group.id,
          identityId: 'identity-1',
          label: 'Server',
          hostname: 'example.com',
          username: 'admin',
          colorTag: 'blue',
          jumpHostId: jumpHost.id,
        );

        await repository.saveHost(
          id: host.id,
          workspaceId: host.workspaceId,
          label: 'Server',
          hostname: host.hostname,
        );

        final updated = await repository.getHostById(host.id);
        expect(updated, isNotNull);
        expect(updated!.groupId, isNull);
        expect(updated.identityId, isNull);
        expect(updated.username, isNull);
        expect(updated.colorTag, isNull);
        expect(updated.jumpHostId, isNull);
      },
    );

    test(
      'clears nullable group fields when an existing group is edited',
      () async {
        final parent = await repository.saveHostGroup(
          workspaceId: 'workspace-1',
          name: 'Parent',
        );
        final group = await repository.saveHostGroup(
          workspaceId: 'workspace-1',
          parentId: parent.id,
          name: 'Servers',
          colorTag: 'blue',
        );

        await repository.saveHostGroup(
          id: group.id,
          workspaceId: group.workspaceId,
          name: group.name,
        );

        final updated = await repository.getHostGroupById(group.id);
        expect(updated, isNotNull);
        expect(updated!.parentId, isNull);
        expect(updated.colorTag, isNull);
      },
    );
  });
}
