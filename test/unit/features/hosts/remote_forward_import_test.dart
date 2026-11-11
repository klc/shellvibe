import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/core/network/ssh_session_manager.dart';
import 'package:shellvibe/core/network/tunnel_engine.dart';
import 'package:shellvibe/features/hosts/data/services/ssh_config_import_service.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/tunnels/data/repositories/tunnel_repository.dart';
import 'package:shellvibe/features/tunnels/domain/services/tunnel_ssh_pool.dart';
import 'package:shellvibe/features/tunnels/presentation/providers/tunnels_providers.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/features/vault/domain/models/identity_model.dart';
import 'package:shellvibe/features/workspaces/presentation/providers/workspace_provider.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// Records what the tunnel would listen on and connect to, without a socket.
class _RecordingEngine extends TunnelEngine {
  final remoteForwards =
      <({int remotePort, String localHost, int localPort})>[];

  @override
  Future<void> startRemoteForward({
    required String ruleId,
    required String hostId,
    required SSHClient sshClient,
    required int remotePort,
    required String localHost,
    required int localPort,
  }) async {
    remoteForwards.add((
      remotePort: remotePort,
      localHost: localHost,
      localPort: localPort,
    ));
  }
}

class _FakeClient implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePool implements TunnelSshPool {
  @override
  Future<SSHClient> acquire({
    required String ruleId,
    required HostModel host,
    IdentityModel? identity,
    HostKeyPromptCallback? onHostKeyPrompt,
  }) async => _FakeClient();

  @override
  Future<void> release(String ruleId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeActiveWorkspace extends ActiveWorkspaceIdNotifier {
  @override
  String build() => 'default';
}

class _FakeVaultKeyService extends VaultKeyService {
  _FakeVaultKeyService()
    : super(
        encryptionEngine: EncryptionEngine(),
        secureStorageService: SecureStorageService(),
      );

  @override
  Future<SecretKey> getDek() async => SecretKey(List<int>.filled(32, 7));
}

void main() {
  test(
    'an imported RemoteForward listens on the server port and connects to the '
    'local destination',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.workspacesDao.insertWorkspace(
        WorkspacesCompanion.insert(
          id: 'default',
          name: 'Default Workspace',
          createdAt: DateTime.now(),
        ),
      );
      await SshConfigImportService(
        db: db,
        vaultKeyService: _FakeVaultKeyService(),
        encryptionEngine: EncryptionEngine(),
        homePath: '/home/user',
        environment: const {},
        readFile: (_) => null,
        listDir: (_) => null,
      ).importConfig(
        path: 'config',
        // ssh -R semantics: the server listens on 5432, and every connection
        // to it is carried to localhost:15432 on this machine.
        content: 'Host db\n  RemoteForward 5432 localhost:15432\n',
        options: const SshConfigImportOptions(
          workspaceId: 'default',
          importIdentityFiles: false,
        ),
      );

      final engine = _RecordingEngine();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          activeWorkspaceIdProvider.overrideWith(_FakeActiveWorkspace.new),
          tunnelEngineProvider.overrideWithValue(engine),
          tunnelSshPoolProvider.overrideWithValue(_FakePool()),
        ],
      );
      addTearDown(container.dispose);
      container.listen(tunnelsProvider, (_, _) {});

      final rule = (await TunnelRepository(
        db.tunnelsDao,
      ).getRulesByWorkspace('default')).single;
      await container.read(tunnelsProvider.notifier).startRule(rule);

      expect(engine.remoteForwards, [
        (remotePort: 5432, localHost: 'localhost', localPort: 15432),
      ]);
    },
  );
}
