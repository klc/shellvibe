import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/hosts/data/repositories/hosts_repository.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/hosts/domain/services/ssh_connect_planner.dart';
import 'package:shellvibe/features/vault/domain/models/identity_model.dart';
import 'package:shellvibe/shared/database/app_database.dart';

void main() {
  late AppDatabase db;
  late SshConnectPlanner planner;

  IdentityModel identity({
    required String username,
    String? password,
    String? privateKey,
    String? passphrase,
  }) => IdentityModel(
    id: 'i1',
    workspaceId: 'default',
    title: 'Stored identity',
    username: username,
    authType: password == null ? 'key' : 'password',
    password: password,
    privateKey: privateKey,
    passphrase: passphrase,
    createdAt: DateTime.now(),
  );

  HostModel host({
    required String id,
    String hostname = 'example.test',
    String? username,
    String? jumpHostId,
    int port = 22,
  }) => HostModel(
    id: id,
    workspaceId: 'default',
    label: id,
    hostname: hostname,
    username: username,
    port: port,
    jumpHostId: jumpHostId,
    createdAt: DateTime.now(),
  );

  Future<void> insert(HostModel model) async {
    await db.hostsDao.insertHost(
      HostsCompanion.insert(
        id: model.id,
        workspaceId: model.workspaceId,
        label: model.label,
        hostname: model.hostname,
        createdAt: model.createdAt,
        jumpHostId: Value(model.jumpHostId),
      ),
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'default',
        name: 'Default Workspace',
        createdAt: DateTime.now(),
      ),
    );
    planner = SshConnectPlanner(HostsRepository(hostsDao: db.hostsDao));
  });

  tearDown(() async => db.close());

  group('resolveJumpChain', () {
    test('is empty for a host with no jump host', () async {
      expect(await planner.resolveJumpChain(host(id: 'target')), isEmpty);
    });

    test('returns the hops in dial order, furthest bastion first', () async {
      await insert(host(id: 'outer'));
      await insert(host(id: 'inner', jumpHostId: 'outer'));

      final chain = await planner.resolveJumpChain(
        host(id: 'target', jumpHostId: 'inner'),
      );

      expect(chain.map((h) => h.id), ['outer', 'inner']);
    });

    test('rejects a cycle instead of looping', () async {
      // Written as two inserts plus an update: the foreign key means neither
      // half of a cycle can be inserted while the other does not exist yet.
      await insert(host(id: 'b'));
      await insert(host(id: 'a', jumpHostId: 'b'));
      await db.hostsDao.updateHostById(
        'b',
        const HostsCompanion(jumpHostId: Value('a')),
      );

      expect(
        () => planner.resolveJumpChain(host(id: 'target', jumpHostId: 'a')),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects a jump host that has been deleted', () async {
      expect(
        () => planner.resolveJumpChain(host(id: 'target', jumpHostId: 'gone')),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('buildConnectConfig', () {
    test('prefers the host\'s own username', () {
      final config = planner.buildConnectConfig(
        host(id: 'h', username: 'ops'),
        identity(username: 'vault'),
      );
      expect(config.username, 'ops');
    });

    test('falls back to a user@host prefix, which it strips', () {
      final config = planner.buildConnectConfig(
        host(id: 'h', hostname: 'deploy@example.test'),
        null,
      );
      expect(config.username, 'deploy');
      expect(config.hostname, 'example.test');
    });

    test('falls back to the identity, then to the OS user', () {
      expect(
        planner
            .buildConnectConfig(
              host(id: 'h'),
              identity(username: 'vault'),
            )
            .username,
        'vault',
      );
      expect(
        planner.buildConnectConfig(host(id: 'h'), null).username,
        Platform.environment['USER'] ??
            Platform.environment['USERNAME'] ??
            '',
      );
    });

    test('carries the identity\'s secrets and the host\'s port', () {
      final config = planner.buildConnectConfig(
        host(id: 'h', port: 2222),
        identity(
          username: 'ops',
          password: 'pw',
          privateKey: 'pem',
          passphrase: 'phrase',
        ),
      );
      expect(config.port, 2222);
      expect(config.password, 'pw');
      expect(config.privateKeyPem, 'pem');
      expect(config.passphrase, 'phrase');
    });
  });
}
