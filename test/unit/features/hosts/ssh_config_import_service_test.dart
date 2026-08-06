import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:terly2/core/crypto/encryption_engine.dart';
import 'package:terly2/features/hosts/data/services/ssh_config_import_service.dart';
import 'package:terly2/features/vault/data/vault_key_service.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/storage/secure_storage_service.dart';

const _kWorkspaceId = 'default';

/// Vault key service that always hands out the same DEK — no platform storage.
class _FakeVaultKeyService extends VaultKeyService {
  _FakeVaultKeyService()
    : super(
        encryptionEngine: EncryptionEngine(),
        secureStorageService: SecureStorageService(),
      );

  @override
  Future<SecretKey> getDek() async => SecretKey(List<int>.filled(32, 7));
}

/// Vault key service that behaves like a locked master-password vault.
class _LockedVaultKeyService extends VaultKeyService {
  _LockedVaultKeyService()
    : super(
        encryptionEngine: EncryptionEngine(),
        secureStorageService: SecureStorageService(),
      );

  @override
  Future<SecretKey> getDek() async => throw const VaultLockedException();
}

/// Encryption engine that fails to encrypt plaintext containing [trigger],
/// used to force a mid-transaction failure.
class _ExplodingEncryptionEngine extends EncryptionEngine {
  final String trigger;

  _ExplodingEncryptionEngine(this.trigger);

  @override
  Future<String> encrypt({
    required String plaintext,
    required SecretKey secretKey,
  }) {
    if (plaintext.contains(trigger)) {
      throw CryptoException('injected encrypt failure');
    }
    return super.encrypt(plaintext: plaintext, secretKey: secretKey);
  }
}

void main() {
  late AppDatabase db;
  late Map<String, String> fs;
  late SshConfigImportService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: _kWorkspaceId,
        name: 'Default Workspace',
        createdAt: DateTime.now(),
      ),
    );
    fs = {
      '/home/user/.ssh/id_ed25519':
          '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----\n',
      '/home/user/.ssh/id_rsa':
          '-----BEGIN OPENSSH PRIVATE KEY-----\nxyz\n-----END OPENSSH PRIVATE KEY-----\n',
      '/home/user/.ssh/id_ed25519.pub': 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 key',
    };
    service = SshConfigImportService(
      db: db,
      vaultKeyService: _FakeVaultKeyService(),
      encryptionEngine: EncryptionEngine(),
      homePath: '/home/user',
      environment: const {},
      readFile: (p) => fs[p],
      listDir: (d) => null,
    );
  });

  tearDown(() async {
    await db.close();
  });

  SshConfigImportOptions options({
    SshConfigConflictPolicy conflict = SshConfigConflictPolicy.skip,
    bool keys = true,
    bool tunnels = true,
    bool jumpHosts = true,
  }) {
    return SshConfigImportOptions(
      workspaceId: _kWorkspaceId,
      conflictPolicy: conflict,
      importIdentityFiles: keys,
      importTunnels: tunnels,
      createMissingJumpHosts: jumpHosts,
    );
  }

  Future<List<Host>> hosts() => db.hostsDao.getHostsByWorkspace(_kWorkspaceId);
  Future<List<Identity>> identities() =>
      db.identitiesDao.getIdentitiesByWorkspace(_kWorkspaceId);

  group('SshConfigImportService', () {
    test('imports plain hosts with resolved fields', () async {
      final result = await service.importConfig(
        path: 'config',
        content: 'Host web\n  HostName web.example.com\n  User deploy\n'
            '  Port 2222\nHost db\n  HostName db.example.com\n',
        options: options(keys: false),
      );

      expect(result.hostsAdded, 2);
      expect(result.hostsSkipped, 0);
      expect(result.hostsUpdated, 0);

      final rows = await hosts();
      expect(rows, hasLength(2));
      final web = rows.firstWhere((h) => h.label == 'web');
      expect(web.hostname, 'web.example.com');
      expect(web.username, 'deploy');
      expect(web.port, 2222);
      expect(web.workspaceId, _kWorkspaceId);
      expect(web.protocol, 'ssh');
      final dbHost = rows.firstWhere((h) => h.label == 'db');
      expect(dbHost.hostname, 'db.example.com');
      expect(dbHost.port, 22);
    });

    test('imports identity files encrypted and deduplicates by content',
        () async {
      final result = await service.importConfig(
        path: 'config',
        content: 'Host web\n  IdentityFile ~/.ssh/id_ed25519\n'
            'Host api\n  IdentityFile /home/user/.ssh/id_ed25519\n'
            'Host old\n  IdentityFile /home/user/.ssh/id_rsa\n',
        options: options(),
      );

      expect(result.identitiesAdded, 2);
      final rows = await identities();
      expect(rows, hasLength(2));
      expect(rows.every((i) => i.authType == 'key'), isTrue);
      expect(rows.every((i) => i.privateKeyEncrypted != null), isTrue);
      expect(
        rows.every((i) => i.privateKeyEncrypted!.contains('OPENSSH PRIVATE')),
        isFalse,
        reason: 'keys must be encrypted at rest, never plaintext',
      );

      final hostRows = await hosts();
      final web = hostRows.firstWhere((h) => h.label == 'web');
      final api = hostRows.firstWhere((h) => h.label == 'api');
      final old = hostRows.firstWhere((h) => h.label == 'old');
      expect(web.identityId, api.identityId,
          reason: 'same key content shares one identity');
      expect(old.identityId, isNot(web.identityId));
      expect(rows.firstWhere((i) => i.id == web.identityId).username, '');
    });

    test('public key files are skipped with a warning', () async {
      final result = await service.importConfig(
        path: 'config',
        content:
            'Host web\n  IdentityFile /home/user/.ssh/id_ed25519.pub\n',
        options: options(),
      );

      expect(result.identitiesAdded, 0);
      expect(await identities(), isEmpty);
      expect(
        result.warnings.any((w) => w.message.contains('public key')),
        isTrue,
      );
    });

    test('unreadable identity files warn but hosts still import', () async {
      final result = await service.importConfig(
        path: 'config',
        content: 'Host web\n  IdentityFile /missing/id_ed25519\n',
        options: options(),
      );

      expect(result.hostsAdded, 1);
      expect((await hosts()).single.identityId, isNull);
      expect(
        result.warnings.any((w) => w.message.contains('not readable')),
        isTrue,
      );
    });

    test('locked vault aborts identity import with VaultLockedException',
        () async {
      final locked = SshConfigImportService(
        db: db,
        vaultKeyService: _LockedVaultKeyService(),
        encryptionEngine: EncryptionEngine(),
        homePath: '/home/user',
        environment: const {},
        readFile: (p) => fs[p],
        listDir: (d) => null,
      );

      await expectLater(
        locked.importConfig(
          path: 'config',
          content: 'Host web\n  IdentityFile ~/.ssh/id_ed25519\n',
          options: options(),
        ),
        throwsA(isA<VaultLockedException>()),
      );
      expect(await hosts(), isEmpty, reason: 'nothing may be written');
    });

    test('conflict policy: skip keeps the existing host', () async {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'existing',
          workspaceId: _kWorkspaceId,
          label: 'web',
          hostname: 'old.example.com',
          username: Value('old'),
          createdAt: DateTime.now(),
        ),
      );
      final result = await service.importConfig(
        path: 'config',
        content: 'Host web\n  HostName new.example.com\n',
        options: options(conflict: SshConfigConflictPolicy.skip, keys: false),
      );

      expect(result.hostsSkipped, 1);
      final row = (await hosts()).single;
      expect(row.hostname, 'old.example.com');
    });

    test('conflict policy: overwrite replaces connection fields', () async {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'existing',
          workspaceId: _kWorkspaceId,
          label: 'web',
          hostname: 'old.example.com',
          username: Value('old'),
          createdAt: DateTime.now(),
        ),
      );
      final result = await service.importConfig(
        path: 'config',
        content: 'Host web\n  HostName new.example.com\n  User new\n',
        options: options(conflict: SshConfigConflictPolicy.overwrite,
            keys: false),
      );

      expect(result.hostsUpdated, 1);
      final row = (await hosts()).single;
      expect(row.id, 'existing', reason: 'same row, not a new one');
      expect(row.hostname, 'new.example.com');
      expect(row.username, 'new');
    });

    test('conflict policy: duplicate suffixes the label', () async {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'existing',
          workspaceId: _kWorkspaceId,
          label: 'web',
          hostname: 'old.example.com',
          createdAt: DateTime.now(),
        ),
      );
      final result = await service.importConfig(
        path: 'config',
        content: 'Host web\n  HostName new.example.com\n',
        options: options(conflict: SshConfigConflictPolicy.duplicate,
            keys: false),
      );

      expect(result.hostsAdded, 1);
      final rows = await hosts();
      expect(rows, hasLength(2));
      expect(rows.map((h) => h.label).toSet(), {'web', 'web (2)'});
    });

    test('ProxyJump links to an imported alias', () async {
      final result = await service.importConfig(
        path: 'config',
        content: 'Host bastion\n  HostName bastion.example.com\n'
            'Host web\n  ProxyJump bastion\n',
        options: options(keys: false),
      );

      expect(result.jumpHostsAdded, 0);
      final rows = await hosts();
      final bastion = rows.firstWhere((h) => h.label == 'bastion');
      final web = rows.firstWhere((h) => h.label == 'web');
      expect(web.jumpHostId, bastion.id);
    });

    test('ProxyJump to an unknown host creates a minimal jump host', () async {
      final result = await service.importConfig(
        path: 'config',
        content: 'Host web\n  ProxyJump user@bastion:2222\n',
        options: options(keys: false),
      );

      expect(result.jumpHostsAdded, 1);
      final rows = await hosts();
      expect(rows, hasLength(2));
      final bastion = rows.firstWhere((h) => h.label == 'bastion');
      expect(bastion.hostname, 'bastion');
      expect(bastion.username, 'user');
      expect(bastion.port, 2222);
      expect(rows.firstWhere((h) => h.label == 'web').jumpHostId, bastion.id);
    });

    test('ProxyJump creation can be disabled with a warning', () async {
      final result = await service.importConfig(
        path: 'config',
        content: 'Host web\n  ProxyJump bastion\n',
        options: options(keys: false, jumpHosts: false),
      );

      expect(result.jumpHostsAdded, 0);
      expect((await hosts()).single.jumpHostId, isNull);
      expect(
        result.warnings.any((w) => w.message.contains('jump link skipped')),
        isTrue,
      );
    });

    test('forwards become tunnel rules on the imported host', () async {
      final result = await service.importConfig(
        path: 'config',
        content: 'Host web\n  LocalForward 8080 localhost:80\n'
            '  DynamicForward 1080\n',
        options: options(keys: false),
      );

      expect(result.tunnelsAdded, 2);
      final host = (await hosts()).single;
      final rules = await db.tunnelsDao.getRulesForHost(host.id);
      expect(rules, hasLength(2));
      final local = rules.firstWhere((r) => r.type == 'local');
      expect(local.localPort, 8080);
      expect(local.remoteHost, 'localhost');
      expect(local.remotePort, 80);
      expect(rules.any((r) => r.type == 'dynamic' && r.localPort == 1080),
          isTrue);
    });

    test('overwrite replaces the existing host tunnels', () async {
      final hostId = 'existing';
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: hostId,
          workspaceId: _kWorkspaceId,
          label: 'web',
          hostname: 'old.example.com',
          createdAt: DateTime.now(),
        ),
      );
      await db.tunnelsDao.insertRule(
        PortForwardRulesCompanion.insert(
          id: 'rule1',
          hostId: hostId,
          type: 'local',
          localPort: 1111,
          remoteHost: Value('localhost'),
          remotePort: Value(80),
        ),
      );
      await service.importConfig(
        path: 'config',
        content: 'Host web\n  LocalForward 8080 localhost:80\n',
        options: options(conflict: SshConfigConflictPolicy.overwrite,
            keys: false),
      );

      final rules = await db.tunnelsDao.getRulesForHost(hostId);
      expect(rules, hasLength(1));
      expect(rules.single.localPort, 8080);
    });

    test('tunnels are skipped when importTunnels is false', () async {
      final result = await service.importConfig(
        path: 'config',
        content: 'Host web\n  LocalForward 8080 localhost:80\n',
        options: options(keys: false, tunnels: false),
      );
      expect(result.tunnelsAdded, 0);
    });

    test('a failing write rolls the whole import back', () async {
      // Inject an encryption failure for one key mid-transaction: the host
      // imported before it must not survive the rollback.
      fs['/boom/key'] =
          '-----BEGIN OPENSSH PRIVATE KEY-----\nboom\n'
          '-----END OPENSSH PRIVATE KEY-----\n';
      final exploding = SshConfigImportService(
        db: db,
        vaultKeyService: _FakeVaultKeyService(),
        encryptionEngine: _ExplodingEncryptionEngine('boom'),
        homePath: '/home/user',
        environment: const {},
        readFile: (p) => fs[p],
        listDir: (d) => null,
      );

      await expectLater(
        exploding.importConfig(
          path: 'config',
          content: 'Host web\n  IdentityFile ~/.ssh/id_ed25519\n'
              'Host bad\n  IdentityFile /boom/key\n',
          options: options(),
        ),
        throwsA(isA<CryptoException>()),
      );
      expect(await hosts(), isEmpty, reason: 'transaction must roll back');
      expect(await identities(), isEmpty);
    });

    test(
        'duplicate policy still links the jump host and imports tunnels for '
        'the suffixed host', () async {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'existing',
          workspaceId: _kWorkspaceId,
          label: 'web',
          hostname: 'old.example.com',
          createdAt: DateTime.now(),
        ),
      );
      final result = await service.importConfig(
        path: 'config',
        content: 'Host web\n  HostName new.example.com\n'
            '  LocalForward 8080 localhost:80\n'
            '  ProxyJump bastion.example.com\n',
        options: options(conflict: SshConfigConflictPolicy.duplicate,
            keys: false),
      );

      expect(result.hostsAdded, 1, reason: 'the duplicated host itself');
      expect(result.jumpHostsAdded, 1,
          reason: 'bastion.example.com has no existing/imported match');
      final rows = await hosts();
      final duplicated = rows.firstWhere((h) => h.label == 'web (2)');
      expect(duplicated.jumpHostId, isNotNull,
          reason: 'duplicate must still resolve ProxyJump for the new host');

      final rules = await db.tunnelsDao.getRulesByWorkspace(_kWorkspaceId);
      expect(
        rules.any((r) => r.hostId == duplicated.id && r.localPort == 8080),
        isTrue,
        reason: 'duplicate must still import the port-forward rule',
      );
    });

    test('skip policy imports no identity for the skipped host', () async {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'existing',
          workspaceId: _kWorkspaceId,
          label: 'web',
          hostname: 'old.example.com',
          createdAt: DateTime.now(),
        ),
      );
      final result = await service.importConfig(
        path: 'config',
        content: 'Host web\n  IdentityFile ~/.ssh/id_ed25519\n',
        options: options(conflict: SshConfigConflictPolicy.skip),
      );

      expect(result.hostsSkipped, 1);
      expect(result.identitiesAdded, 0,
          reason: 'skip must bail out before any identity work');
      expect(await identities(), isEmpty);
    });

    test('overwrite clears jumpHostId when the new config has no ProxyJump',
        () async {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'bastion',
          workspaceId: _kWorkspaceId,
          label: 'bastion',
          hostname: 'bastion.example.com',
          createdAt: DateTime.now(),
        ),
      );
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'existing',
          workspaceId: _kWorkspaceId,
          label: 'web',
          hostname: 'old.example.com',
          jumpHostId: const Value('bastion'),
          createdAt: DateTime.now(),
        ),
      );
      await service.importConfig(
        path: 'config',
        content: 'Host web\n  HostName new.example.com\n',
        options: options(conflict: SshConfigConflictPolicy.overwrite,
            keys: false),
      );

      final row = (await hosts()).firstWhere((h) => h.id == 'existing');
      expect(row.jumpHostId, isNull);
    });

    test('passphrase-protected identity files still import with a warning',
        () async {
      fs['/home/user/.ssh/id_locked'] =
          '-----BEGIN RSA PRIVATE KEY-----\n'
          'Proc-Type: 4,ENCRYPTED\n'
          'DEK-Info: AES-128-CBC,ABCD\n\n'
          'encryptedbase64stuff\n'
          '-----END RSA PRIVATE KEY-----\n';
      final result = await service.importConfig(
        path: 'config',
        content: 'Host web\n  IdentityFile /home/user/.ssh/id_locked\n',
        options: options(),
      );

      expect(result.identitiesAdded, 1,
          reason: 'encrypted keys are still imported, just flagged');
      expect(
        result.warnings.any((w) => w.message.contains('passphrase-protected')),
        isTrue,
      );
    });
  });
}
