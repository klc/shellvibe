import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/ssh_session_manager.dart';
import 'package:shellvibe/features/hosts/data/repositories/hosts_repository.dart';
import 'package:shellvibe/features/hosts/domain/models/host_model.dart';
import 'package:shellvibe/features/hosts/domain/services/ssh_connect_planner.dart';
import 'package:shellvibe/features/tunnels/domain/services/tunnel_ssh_pool.dart';
import 'package:shellvibe/shared/database/app_database.dart';

/// A client that is never dialed: the pool only ever asks whether it is
/// closed, and hands it back to the tunnel engine.
class _FakeClient implements SSHClient {
  bool closed = false;

  @override
  bool get isClosed => closed;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeManager implements SSHSessionManager {
  _FakeManager({this.failWith});

  final Exception? failWith;
  final _clientChanges = StreamController<SSHClient?>.broadcast();
  final List<SSHConnectConfig> connects = [];
  _FakeClient? _client;
  bool closeCalled = false;

  @override
  SSHClient? get client => _client;

  @override
  Stream<SSHClient?> get clientChanges => _clientChanges.stream;

  @override
  bool get isConnected => _client != null && !_client!.isClosed;

  @override
  Future<SSHClient> connect(
    SSHConnectConfig config, {
    SSHClient? viaClient,
  }) async {
    connects.add(config);
    if (failWith != null) throw failWith!;
    return _client = _FakeClient();
  }

  /// Mimics the keep-alive noticing the connection is gone.
  void dropConnection() {
    _client?.closed = true;
    _clientChanges.add(null);
  }

  @override
  Future<void> close() async {
    closeCalled = true;
    _client = null;
    await _clientChanges.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

void main() {
  late AppDatabase db;
  late List<_FakeManager> managers;
  late TunnelSshPool pool;
  Exception? connectFailure;

  HostModel host({required String id, String? jumpHostId}) => HostModel(
    id: id,
    workspaceId: 'default',
    label: id,
    hostname: '$id.example.test',
    username: 'ops',
    port: 22,
    jumpHostId: jumpHostId,
    createdAt: DateTime.now(),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'default',
        name: 'Default Workspace',
        createdAt: DateTime.now(),
      ),
    );
    managers = [];
    connectFailure = null;
    pool = TunnelSshPool(
      planner: SshConnectPlanner(HostsRepository(hostsDao: db.hostsDao)),
      createSessionManager: () {
        final manager = _FakeManager(failWith: connectFailure);
        managers.add(manager);
        return manager;
      },
      readIdentity: (_) async => null,
    );
  });

  tearDown(() async {
    await pool.dispose();
    await db.close();
  });

  test('dials once and reuses that client for a second rule', () async {
    final target = host(id: 'web');

    final first = await pool.acquire(ruleId: 'r1', host: target);
    final second = await pool.acquire(ruleId: 'r2', host: target);

    expect(identical(first, second), isTrue);
    expect(managers, hasLength(1));
    expect(managers.single.connects.single.hostname, 'web.example.test');
  });

  test('two rules starting at once share one dial', () async {
    final target = host(id: 'web');

    final clients = await Future.wait([
      pool.acquire(ruleId: 'r1', host: target),
      pool.acquire(ruleId: 'r2', host: target),
    ]);

    expect(identical(clients[0], clients[1]), isTrue);
    expect(managers, hasLength(1));
  });

  test('closes the session only once the last rule releases it', () async {
    final target = host(id: 'web');
    await pool.acquire(ruleId: 'r1', host: target);
    await pool.acquire(ruleId: 'r2', host: target);

    await pool.release('r1');
    expect(pool.holds('web'), isTrue);
    expect(managers.single.closeCalled, isFalse);

    await pool.release('r2');
    expect(pool.holds('web'), isFalse);
    expect(managers.single.closeCalled, isTrue);
  });

  test('releasing a rule the pool never dialed for is a no-op', () async {
    await pool.acquire(ruleId: 'r1', host: host(id: 'web'));

    await pool.release('rule-from-a-terminal-tab');

    expect(pool.holds('web'), isTrue);
    expect(managers.single.closeCalled, isFalse);
  });

  test('forgets a session whose connection dropped, and redials', () async {
    final target = host(id: 'web');
    await pool.acquire(ruleId: 'r1', host: target);

    managers.single.dropConnection();
    await Future<void>.delayed(Duration.zero);
    expect(pool.holds('web'), isFalse);

    await pool.acquire(ruleId: 'r1', host: target);
    expect(managers, hasLength(2));
  });

  test('dials every jump hop before the target, nearest hop last', () async {
    for (final id in ['outer', 'inner']) {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: id,
          workspaceId: 'default',
          label: id,
          hostname: '$id.example.test',
          createdAt: DateTime.now(),
          jumpHostId: Value(id == 'inner' ? 'outer' : null),
        ),
      );
    }

    await pool.acquire(
      ruleId: 'r1',
      host: host(id: 'web', jumpHostId: 'inner'),
    );

    expect(managers, hasLength(3));
    expect(
      managers.map((m) => m.connects.single.hostname),
      ['outer.example.test', 'inner.example.test', 'web.example.test'],
    );
  });

  test('a failed connect leaves nothing pooled and nothing to retry', () async {
    connectFailure = Exception('auth failed');

    await expectLater(
      pool.acquire(ruleId: 'r1', host: host(id: 'web')),
      throwsA(isA<Exception>()),
    );

    expect(pool.holds('web'), isFalse);
    expect(pool.connectedHostIds, isEmpty);
  });
}
