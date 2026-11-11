import 'package:dartssh2/dartssh2.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/ssh_session_manager.dart';
import 'package:shellvibe/core/network/tunnel_engine.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/tunnels/domain/models/tunnel_rule_model.dart';
import 'package:shellvibe/features/tunnels/domain/services/tunnel_ssh_pool.dart';
import 'package:shellvibe/features/tunnels/presentation/providers/tunnels_providers.dart';
import 'package:shellvibe/features/vault/domain/models/identity_model.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

/// "Auto-start with SSH Connection" was saved and synced but nothing read it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _RecordingEngine engine;
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
    for (final id in ['h1', 'h2']) {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: id,
          workspaceId: 'default',
          label: id,
          hostname: '$id.example.com',
          createdAt: DateTime.now(),
        ),
      );
    }
    Future<void> rule(String id, String hostId, {required bool autoStart}) =>
        db.tunnelsDao.insertRule(
          PortForwardRulesCompanion.insert(
            id: id,
            hostId: hostId,
            type: 'local',
            localPort: 5432,
            remoteHost: const Value('127.0.0.1'),
            remotePort: const Value(5432),
            autoStart: Value(autoStart),
          ),
        );
    await rule('auto-h1', 'h1', autoStart: true);
    await rule('manual-h1', 'h1', autoStart: false);
    await rule('auto-h2', 'h2', autoStart: true);

    engine = _RecordingEngine();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        tunnelEngineProvider.overrideWithValue(engine),
        tunnelSshPoolProvider.overrideWithValue(_FakePool()),
      ],
    );
    container.listen(tunnelsProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('starts only the auto-start rules of the host that connected', () async {
    await container.read(tunnelsProvider.notifier).autoStartRulesForHost('h1');

    expect(engine.started, ['auto-h1']);
  });

  test('leaves a rule that is already running alone', () async {
    engine.active.add('auto-h1');

    await container.read(tunnelsProvider.notifier).autoStartRulesForHost('h1');

    expect(engine.started, isEmpty);
  });

  test('a forward with no remote port is refused, not given one', () async {
    // The bug this pins: a missing port was silently replaced with 80 (or
    // 8080 for -R), forwarding somewhere the user never chose.
    await expectLater(
      container
          .read(tunnelsProvider.notifier)
          .startRule(
            const TunnelRuleModel(
              id: 'no-port',
              hostId: 'h1',
              type: 'local',
              localPort: 5432,
              remoteHost: '127.0.0.1',
            ),
          ),
      throwsStateError,
    );
    expect(engine.started, isEmpty);
  });
}

final class _RecordingEngine extends TunnelEngine {
  final List<String> started = [];
  final Set<String> active = {};

  @override
  bool isTunnelActive(String ruleId) => active.contains(ruleId);

  @override
  Future<void> startLocalForward({
    required String ruleId,
    required String hostId,
    required SSHClient sshClient,
    required int localPort,
    required String remoteHost,
    required int remotePort,
  }) async {
    started.add(ruleId);
  }
}

final class _FakePool extends Fake implements TunnelSshPool {
  @override
  Future<SSHClient> acquire({
    required String ruleId,
    required HostModel host,
    IdentityModel? identity,
    HostKeyPromptCallback? onHostKeyPrompt,
  }) async => _FakeClient();

  @override
  Future<void> release(String ruleId) async {}
}

final class _FakeClient extends Fake implements SSHClient {}
