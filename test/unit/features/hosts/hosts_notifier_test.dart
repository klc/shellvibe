import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:terly2/features/hosts/presentation/notifiers/host_groups_notifier.dart';
import 'package:terly2/features/hosts/presentation/notifiers/hosts_notifier.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/providers/database_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'default',
        name: 'Default Workspace',
        createdAt: DateTime.now(),
      ),
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('HostsNotifier & HostGroupsNotifier Unit Tests', () {
    test('Initial state is empty', () async {
      final hosts = await container.read(hostsNotifierProvider.future);
      final groups = await container.read(hostGroupsNotifierProvider.future);
      expect(hosts, isEmpty);
      expect(groups, isEmpty);
    });

    test('addGroup and updateGroup lifecycle', () async {
      final groupNotifier = container.read(hostGroupsNotifierProvider.notifier);

      await groupNotifier.addGroup(
        workspaceId: 'default',
        name: 'Production',
        colorTag: '#FF0000',
      );

      var groups = await container.read(hostGroupsNotifierProvider.future);
      expect(groups.length, equals(1));
      expect(groups.first.name, equals('Production'));
      expect(groups.first.colorTag, equals('#FF0000'));

      final id = groups.first.id;
      await groupNotifier.updateGroup(
        id: id,
        workspaceId: 'default',
        name: 'Production US-East',
        colorTag: '#00FF00',
      );

      groups = await container.read(hostGroupsNotifierProvider.future);
      expect(groups.first.name, equals('Production US-East'));

      await groupNotifier.deleteGroup(id);
      groups = await container.read(hostGroupsNotifierProvider.future);
      expect(groups, isEmpty);
    });

    test('addHost, updateHost and deleteHost CRUD with username', () async {
      final hostsNotifier = container.read(hostsNotifierProvider.notifier);

      await hostsNotifier.addHost(
        workspaceId: 'default',
        label: 'AWS EC2 Web',
        hostname: '10.0.0.5',
        username: 'admin',
        port: 22,
        protocol: 'ssh',
      );

      var hosts = await container.read(hostsNotifierProvider.future);
      expect(hosts.length, equals(1));
      expect(hosts.first.label, equals('AWS EC2 Web'));
      expect(hosts.first.hostname, equals('10.0.0.5'));
      expect(hosts.first.username, equals('admin'));

      final id = hosts.first.id;
      await hostsNotifier.updateHost(
        id: id,
        workspaceId: 'default',
        label: 'AWS EC2 Web Primary',
        hostname: '10.0.0.6',
        username: 'root',
        port: 2222,
        protocol: 'ssh',
      );

      hosts = await container.read(hostsNotifierProvider.future);
      expect(hosts.first.label, equals('AWS EC2 Web Primary'));
      expect(hosts.first.hostname, equals('10.0.0.6'));
      expect(hosts.first.username, equals('root'));
      expect(hosts.first.port, equals(2222));

      await hostsNotifier.deleteHost(id);
      hosts = await container.read(hostsNotifierProvider.future);
      expect(hosts, isEmpty);
    });
  });
}
