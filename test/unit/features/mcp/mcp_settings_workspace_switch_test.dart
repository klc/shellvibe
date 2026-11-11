import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/mcp/data/mcp_host_connector.dart';
import 'package:shellvibe/features/mcp/data/mcp_providers.dart';
import 'package:shellvibe/features/mcp/data/mcp_server_controller.dart';
import 'package:shellvibe/features/mcp/data/mcp_session_pool.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_audit_repository.dart';
import 'package:shellvibe/features/mcp/data/repositories/mcp_client_repository.dart';
import 'package:shellvibe/features/mcp/presentation/notifiers/mcp_settings_notifier.dart';
import 'package:shellvibe/features/workspaces/domain/models/workspace_model.dart';
import 'package:shellvibe/features/workspaces/presentation/providers/workspace_provider.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/database/daos/mcp_dao.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// Switching workspaces under a running server must move the bridge to the
/// new workspace: otherwise a restarted agent keeps seeing the old one's
/// hosts until the server itself is restarted.
void main() {
  late ProviderContainer container;
  late _FakeController controller;
  late AppDatabase db;

  Future<void> boot(Map<String, String> stored) async {
    controller = _FakeController(
      () => container.read(activeWorkspaceIdProvider),
    );
    final pool = McpSessionPool(connector: _NoConnector());
    addTearDown(pool.dispose);
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        workspacesProvider.overrideWith(
          (ref) async => [
            for (final id in ['a', 'b'])
              WorkspaceModel(id: id, name: id, createdAt: DateTime(2026)),
          ],
        ),
        secureStorageServiceProvider.overrideWithValue(_MemoryStorage(stored)),
        mcpServerControllerProvider.overrideWithValue(controller),
        mcpSessionPoolProvider.overrideWithValue(pool),
        activeWorkspaceIdProvider.overrideWith(_Workspace.new),
      ],
    );
    addTearDown(container.dispose);
    container.listen(mcpSettingsProvider, (_, _) {});
    await settle();
  }

  Future<void> switchTo(String id) async {
    container.read(activeWorkspaceIdProvider.notifier).state = id;
    await settle();
  }

  test('restarts the server for the new workspace', () async {
    await boot({
      'mcp_settings_a': '{"masterEnabled":true}',
      'mcp_settings_b': '{"masterEnabled":true}',
    });
    expect(controller.workspaceId, 'a');

    await switchTo('b');
    expect(controller.workspaceId, 'b');
    expect(controller.stops, 1);
  });

  test('panic keeps AI access off in every workspace', () async {
    final stored = {
      'mcp_settings_a': '{"masterEnabled":true}',
      'mcp_settings_b': '{"masterEnabled":true}',
    };
    await boot(stored);
    expect(controller.isRunning, isTrue);

    await container.read(mcpSettingsProvider.notifier).panic();
    await settle();
    await switchTo('b');

    expect(controller.isRunning, isFalse);
    expect(stored['mcp_settings_b'], contains('"masterEnabled":false'));
  });

  test('panic leaves an audit row for every client it revokes', () async {
    await boot({'mcp_settings_a': '{"masterEnabled":true}'});
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(id: 'b', name: 'b', createdAt: DateTime(2026)),
    );
    await db.mcpDao.insertClient(
      McpClientsCompanion.insert(
        id: 'client-b',
        workspaceId: 'b',
        name: 'Agent',
        tokenHash: 'hash-b',
        createdAt: DateTime(2026),
      ),
    );

    await container.read(mcpSettingsProvider.notifier).panic();

    final rows = await McpAuditRepository(db.mcpDao).query();
    expect(rows.map((r) => (r.tool, r.clientId, r.workspaceId, r.decision)), [
      ('panic', 'client-b', 'b', 'denied'),
    ]);
  });

  test('stops the server when the new workspace has AI access off', () async {
    await boot({'mcp_settings_a': '{"masterEnabled":true}'});
    expect(controller.isRunning, isTrue);

    await switchTo('b');
    expect(controller.isRunning, isFalse);
  });
}

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await pumpEventQueue();
  }
}

class _Workspace extends ActiveWorkspaceIdNotifier {
  @override
  String build() => 'a';
}

class _FakeController extends McpServerController {
  _FakeController(String Function() active)
    : super(
        transportFactory: ({required onRequest, required authenticate}) =>
            throw UnimplementedError(),
        clients: McpClientRepository(_NoDao()),
        onRequest: (_, _, _) async => null,
        isVaultAvailable: () => true,
        activeWorkspaceId: active,
      );

  String? _bound;
  int stops = 0;

  @override
  bool get isRunning => _bound != null;

  @override
  String? get workspaceId => _bound;

  @override
  int? get port => isRunning ? 7433 : null;

  @override
  Future<void> start({bool reinstate = false}) async =>
      _bound = activeWorkspaceId();

  @override
  Future<void> stop() async {
    if (_bound != null) stops++;
    _bound = null;
  }
}

class _NoDao implements McpDao {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoConnector implements McpHostConnector {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _MemoryStorage extends SecureStorageService {
  final Map<String, String> values;

  _MemoryStorage(this.values) : super(storage: const FlutterSecureStorage());

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}
