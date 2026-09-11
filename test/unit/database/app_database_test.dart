import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/database/daos/hosts_dao.dart';
import 'package:shellvibe/shared/database/daos/identities_dao.dart';
import 'package:shellvibe/shared/database/daos/known_hosts_dao.dart';
import 'package:shellvibe/shared/database/daos/tunnels_dao.dart';
import 'package:shellvibe/shared/database/daos/workspaces_dao.dart';

void main() {
  late AppDatabase db;
  late WorkspacesDao workspacesDao;
  late IdentitiesDao identitiesDao;
  late HostsDao hostsDao;
  late KnownHostsDao knownHostsDao;
  late TunnelsDao tunnelsDao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    workspacesDao = db.workspacesDao;
    identitiesDao = db.identitiesDao;
    hostsDao = db.hostsDao;
    knownHostsDao = db.knownHostsDao;
    tunnelsDao = db.tunnelsDao;
  });

  tearDown(() async {
    await db.close();
  });

  group('Drift SQLite Database & DAOs Unit Tests', () {
    test('Workspace CRUD operations', () async {
      final workspace = WorkspacesCompanion.insert(
        id: 'ws-1',
        name: 'Production Workspace',
        colorCode: Value('#FF0000'),
        createdAt: DateTime.now(),
      );

      await workspacesDao.insertWorkspace(workspace);

      final fetched = await workspacesDao.getWorkspaceById('ws-1');
      expect(fetched, isNotNull);
      expect(fetched!.name, equals('Production Workspace'));
      expect(fetched.colorCode, equals('#FF0000'));

      final all = await workspacesDao.getAllWorkspaces();
      expect(
        all.map((workspace) => workspace.id),
        containsAll(['default', 'ws-1']),
      );

      // Update
      await workspacesDao.updateWorkspace(
        fetched.copyWith(name: 'Updated Workspace'),
      );
      final updated = await workspacesDao.getWorkspaceById('ws-1');
      expect(updated!.name, equals('Updated Workspace'));

      // Delete
      await workspacesDao.deleteWorkspace('ws-1');
      expect(await workspacesDao.getWorkspaceById('ws-1'), isNull);
    });

    test('Identity CRUD operations', () async {
      await workspacesDao.insertWorkspace(
        WorkspacesCompanion.insert(
          id: 'ws-1',
          name: 'Default',
          createdAt: DateTime.now(),
        ),
      );

      final identity = IdentitiesCompanion.insert(
        id: 'ident-1',
        workspaceId: 'ws-1',
        title: 'Root SSH Key',
        username: 'root',
        authType: 'key',
        privateKeyEncrypted: Value('EncryptedPrivateKeyPayload'),
        createdAt: DateTime.now(),
      );

      await identitiesDao.insertIdentity(identity);

      final fetched = await identitiesDao.getIdentityById('ident-1');
      expect(fetched, isNotNull);
      expect(fetched!.title, equals('Root SSH Key'));
      expect(fetched.username, equals('root'));
      expect(fetched.authType, equals('key'));
      expect(fetched.privateKeyEncrypted, equals('EncryptedPrivateKeyPayload'));

      final byWs = await identitiesDao.getIdentitiesByWorkspace('ws-1');
      expect(byWs.length, equals(1));

      // Delete
      await identitiesDao.deleteIdentity('ident-1');
      expect(await identitiesDao.getIdentityById('ident-1'), isNull);
    });

    test('Host CRUD operations', () async {
      await workspacesDao.insertWorkspace(
        WorkspacesCompanion.insert(
          id: 'ws-1',
          name: 'Default',
          createdAt: DateTime.now(),
        ),
      );

      await identitiesDao.insertIdentity(
        IdentitiesCompanion.insert(
          id: 'ident-1',
          workspaceId: 'ws-1',
          title: 'Default User',
          username: 'ubuntu',
          authType: 'password',
          createdAt: DateTime.now(),
        ),
      );

      final host = HostsCompanion.insert(
        id: 'host-1',
        workspaceId: 'ws-1',
        identityId: Value('ident-1'),
        label: 'Production Web Server',
        hostname: '192.168.1.100',
        port: Value(2222),
        protocol: Value('ssh'),
        createdAt: DateTime.now(),
      );

      await hostsDao.insertHost(host);

      final fetched = await hostsDao.getHostById('host-1');
      expect(fetched, isNotNull);
      expect(fetched!.label, equals('Production Web Server'));
      expect(fetched.hostname, equals('192.168.1.100'));
      expect(fetched.port, equals(2222));
      expect(fetched.identityId, equals('ident-1'));

      final wsHosts = await hostsDao.getHostsByWorkspace('ws-1');
      expect(wsHosts.length, equals(1));

      // Delete
      await hostsDao.deleteHost('host-1');
      expect(await hostsDao.getHostById('host-1'), isNull);
    });

    test('KnownHosts CRUD & fingerprint lookup operations', () async {
      final entry = KnownHostsCompanion.insert(
        id: 'kh-1',
        hostname: 'example.com',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprintSha256: 'SHA256:abc123def456',
        firstSeenAt: DateTime.now(),
      );

      await knownHostsDao.insertOrUpdateKnownHost(entry);

      final found = await knownHostsDao.findKnownHost('example.com', 22);
      expect(found, isNotNull);
      expect(found!.keyType, equals('ssh-ed25519'));
      expect(found.fingerprintSha256, equals('SHA256:abc123def456'));

      // Not found for wrong port
      final notFound = await knownHostsDao.findKnownHost('example.com', 2222);
      expect(notFound, isNull);

      // Update on conflict
      final updatedEntry = KnownHostsCompanion.insert(
        id: 'kh-1',
        hostname: 'example.com',
        port: 22,
        keyType: 'rsa-sha2-512',
        fingerprintSha256: 'SHA256:newfingerprint',
        firstSeenAt: DateTime.now(),
      );
      await knownHostsDao.insertOrUpdateKnownHost(updatedEntry);

      final reFound = await knownHostsDao.findKnownHost('example.com', 22);
      expect(reFound!.fingerprintSha256, equals('SHA256:newfingerprint'));
      expect(reFound.keyType, equals('rsa-sha2-512'));

      // Delete
      await knownHostsDao.deleteKnownHost('kh-1');
      expect(await knownHostsDao.findKnownHost('example.com', 22), isNull);
    });

    test('TunnelsDao (PortForwardRules) CRUD operations', () async {
      await workspacesDao.insertWorkspace(
        WorkspacesCompanion.insert(
          id: 'ws-1',
          name: 'Default',
          createdAt: DateTime.now(),
        ),
      );

      await hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'host-1',
          workspaceId: 'ws-1',
          label: 'Db Host',
          hostname: 'db.internal',
          createdAt: DateTime.now(),
        ),
      );

      final rule1 = PortForwardRulesCompanion.insert(
        id: 'rule-1',
        hostId: 'host-1',
        type: 'local',
        localPort: 5432,
        remoteHost: Value('127.0.0.1'),
        remotePort: Value(5432),
        autoStart: Value(true),
      );

      final rule2 = PortForwardRulesCompanion.insert(
        id: 'rule-2',
        hostId: 'host-1',
        type: 'dynamic',
        localPort: 1080,
        autoStart: Value(false),
      );

      await tunnelsDao.insertRule(rule1);
      await tunnelsDao.insertRule(rule2);

      final hostRules = await tunnelsDao.getRulesForHost('host-1');
      expect(hostRules.length, equals(2));

      final autoStartRules = await tunnelsDao.getAutoStartRules();
      expect(autoStartRules.length, equals(1));
      expect(autoStartRules.first.id, equals('rule-1'));
      expect(autoStartRules.first.localPort, equals(5432));

      await tunnelsDao.deleteRule('rule-1');
      final remaining = await tunnelsDao.getRulesForHost('host-1');
      expect(remaining.length, equals(1));
      expect(remaining.first.id, equals('rule-2'));
    });
  });
}
