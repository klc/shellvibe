import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/sync_journal.dart';
import 'package:shellvibe/shared/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    db.syncJournal = SyncJournal(db: db, deviceId: 'device-a');
  });

  tearDown(() => db.close());

  Future<void> addHost(String id, String workspaceId) => db.hostsDao.insertHost(
    HostsCompanion.insert(
      id: id,
      workspaceId: workspaceId,
      label: id,
      hostname: '10.0.0.1',
      createdAt: DateTime(2026),
    ),
  );

  Future<List<String>> recordedWorkspaceIds() async => [
    for (final op in await db.select(db.pendingOperations).get())
      if (op.entityType == 'workspaces') op.entityId,
  ];

  test('a workspace made for a row is recorded for sync', () async {
    await addHost('h-1', 'ws-new');

    expect(await db.workspacesDao.getWorkspaceById('ws-new'), isNotNull);
    expect(await recordedWorkspaceIds(), ['ws-new']);
  });

  test('a late write does not bring back a deleted workspace', () async {
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'ws-1',
        name: 'Work',
        createdAt: DateTime(2026),
      ),
    );
    await db.workspacesDao.deleteWorkspace('ws-1');

    await expectLater(addHost('h-late', 'ws-1'), throwsStateError);

    expect(await db.workspacesDao.getWorkspaceById('ws-1'), isNull);
    expect(await db.hostsDao.getHostById('h-late'), isNull);
  });
}
