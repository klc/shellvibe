import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/sync_row_codec.dart';
import 'package:shellvibe/core/sync/sync_row_writer.dart';
import 'package:shellvibe/features/hosts/data/repositories/hosts_repository.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/snippets/presentation/widgets/prod_confirmation.dart';
import 'package:shellvibe/shared/database/app_database.dart';

HostModel host(String id, {String environment = 'dev'}) => HostModel(
  id: id,
  workspaceId: 'w',
  label: id,
  hostname: id,
  environment: environment,
  createdAt: DateTime(2026),
);

void main() {
  test('only prod counts, once each, in order', () {
    final prod = prodHostsOf([
      host('a'),
      host('b', environment: 'prod'),
      host('s', environment: 'staging'),
      host('b', environment: 'prod'),
      host('c', environment: 'prod'),
    ]);
    expect(prod.map((h) => h.id), ['b', 'c']);
  });

  test('a host defaults to dev and isProd follows the name', () {
    expect(host('a').environment, 'dev');
    expect(host('a').isProd, isFalse);
    expect(host('a', environment: 'prod').isProd, isTrue);
    expect(host('a', environment: 'staging').isProd, isFalse);
  });

  group('persistence', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('the environment is saved, read back and edited', () async {
      final repo = HostsRepository(hostsDao: db.hostsDao);
      final saved = await repo.saveHost(
        workspaceId: 'default',
        label: 'db',
        hostname: 'db.example.com',
        environment: 'prod',
      );
      expect(saved.environment, 'prod');
      expect((await repo.getHostById(saved.id))!.isProd, isTrue);

      await repo.saveHost(
        id: saved.id,
        workspaceId: 'default',
        label: 'db',
        hostname: 'db.example.com',
        environment: 'staging',
      );
      expect((await repo.getHostById(saved.id))!.environment, 'staging');
    });

    test('it travels through sync in both directions', () async {
      final repo = HostsRepository(hostsDao: db.hostsDao);
      final saved = await repo.saveHost(
        workspaceId: 'default',
        label: 'db',
        hostname: 'db.example.com',
        environment: 'prod',
      );
      final row = (await db.select(db.hosts).get()).single;
      final encoded = SyncRowCodec.host(row);
      expect(encoded['environment'], 'prod');

      await db.hostsDao.deleteHost(saved.id);
      await SyncRowWriter.write(db, 'hosts', encoded);
      expect((await repo.getHostById(saved.id))!.environment, 'prod');

      // A row from before the column existed is development.
      await SyncRowWriter.write(db, 'hosts', {
        'id': 'old',
        'workspaceId': 'default',
        'label': 'old',
        'hostname': 'old',
        'createdAt': DateTime(2026).toIso8601String(),
      });
      expect((await repo.getHostById('old'))!.environment, 'dev');
    });
  });
}
