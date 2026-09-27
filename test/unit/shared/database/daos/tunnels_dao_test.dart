import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/shared/database/app_database.dart';

/// The queries [TunnelsDao] adds on top of plain row access: which rules
/// start on their own, and which belong to a host or a workspace.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'other',
        name: 'Other',
        createdAt: DateTime.now(),
      ),
    );
    for (final (id, workspace) in [
      ('app', 'default'),
      ('db', 'default'),
      ('elsewhere', 'other'),
    ]) {
      await db.hostsDao.insertHost(
        HostsCompanion.insert(
          id: id,
          workspaceId: workspace,
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
            localPort: 8000 + id.length,
            remoteHost: const Value('127.0.0.1'),
            remotePort: const Value(80),
            autoStart: Value(autoStart),
          ),
        );

    await rule('app-auto', 'app', autoStart: true);
    await rule('app-manual', 'app', autoStart: false);
    await rule('db-auto', 'db', autoStart: true);
    await rule('elsewhere-auto', 'elsewhere', autoStart: true);
  });

  tearDown(() => db.close());

  Set<String> ids(List<PortForwardRule> rules) =>
      rules.map((r) => r.id).toSet();

  test('only rules marked to start on their own are started', () async {
    expect(ids(await db.tunnelsDao.getAutoStartRules()), {
      'app-auto',
      'db-auto',
      'elsewhere-auto',
    });
  });

  test('a host lists its own rules and no one else\'s', () async {
    expect(ids(await db.tunnelsDao.getRulesForHost('app')), {
      'app-auto',
      'app-manual',
    });
  });

  test('a workspace lists the rules of its hosts only', () async {
    expect(ids(await db.tunnelsDao.getRulesByWorkspace('default')), {
      'app-auto',
      'app-manual',
      'db-auto',
    });
    expect(await db.tunnelsDao.getRulesByWorkspace('empty'), isEmpty);
  });
}
