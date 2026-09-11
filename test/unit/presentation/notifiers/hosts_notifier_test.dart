import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellvibe/features/hosts/presentation/notifiers/hosts_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HostsNotifier State Transition Unit Tests', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
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

    test('Initial state loads empty host list', () async {
      final hosts = await container.read(hostsProvider.future);
      expect(hosts, isEmpty);
    });

    test('addHost adds a host to repository and updates notifier state', () async {
      final notifier = container.read(hostsProvider.notifier);

      await notifier.addHost(
        workspaceId: 'default',
        label: 'Production Gateway',
        hostname: 'gateway.prod.com',
        username: 'ubuntu',
        port: 2222,
        protocol: 'ssh',
      );

      final hosts = container.read(hostsProvider).value!;
      expect(hosts.length, equals(1));
      expect(hosts.first.label, equals('Production Gateway'));
      expect(hosts.first.hostname, equals('gateway.prod.com'));
      expect(hosts.first.port, equals(2222));
    });

    test('updateHost edits existing host and updates notifier state', () async {
      final notifier = container.read(hostsProvider.notifier);

      await notifier.addHost(
        workspaceId: 'default',
        label: 'Staging App Server',
        hostname: 'staging.app.com',
        username: 'deploy',
      );

      final initialHosts = container.read(hostsProvider).value!;
      final hostId = initialHosts.first.id;

      await notifier.updateHost(
        id: hostId,
        workspaceId: 'default',
        label: 'Production App Server',
        hostname: 'prod.app.com',
        username: 'deploy',
        port: 22,
      );

      final updatedHosts = container.read(hostsProvider).value!;
      expect(updatedHosts.length, equals(1));
      expect(updatedHosts.first.id, equals(hostId));
      expect(updatedHosts.first.label, equals('Production App Server'));
      expect(updatedHosts.first.hostname, equals('prod.app.com'));
    });

    test('deleteHost removes host from database and notifier state', () async {
      final notifier = container.read(hostsProvider.notifier);

      await notifier.addHost(
        workspaceId: 'default',
        label: 'Temp Host',
        hostname: 'temp.internal',
      );

      final initialHosts = container.read(hostsProvider).value!;
      expect(initialHosts.length, equals(1));
      final hostId = initialHosts.first.id;

      await notifier.deleteHost(hostId);

      final remainingHosts = container.read(hostsProvider).value!;
      expect(remainingHosts, isEmpty);
    });
  });
}
