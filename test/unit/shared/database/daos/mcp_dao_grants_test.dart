import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/shared/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.hostsDao.insertHost(
      HostsCompanion.insert(
        id: 'h-1',
        workspaceId: 'default',
        label: 'H',
        hostname: '10.0.0.1',
        createdAt: DateTime(2026),
      ),
    );
    await db.mcpDao.insertClient(
      McpClientsCompanion.insert(
        id: 'c-1',
        workspaceId: 'default',
        name: 'Agent',
        tokenHash: 'x',
        createdAt: DateTime(2026),
      ),
    );
  });

  tearDown(() => db.close());

  McpHostGrantsCompanion grant(String id, String mode) =>
      McpHostGrantsCompanion.insert(
        id: id,
        clientId: 'c-1',
        hostId: 'h-1',
        mode: mode,
        grantedAt: DateTime(2026),
      );

  test('upserts racing for one pair leave one grant', () async {
    await Future.wait([
      db.mcpDao.upsertGrant(grant('g-1', 'readonly')),
      db.mcpDao.upsertGrant(grant('g-2', 'guarded')),
    ]);

    expect(await db.mcpDao.getGrantsForClient('c-1'), hasLength(1));
    expect(await db.mcpDao.findGrant('c-1', 'h-1'), isNotNull);
  });

  test('the database refuses a second grant for a pair', () async {
    await db.mcpDao.upsertGrant(grant('g-1', 'readonly'));

    await expectLater(
      db.into(db.mcpHostGrants).insert(grant('g-2', 'guarded')),
      throwsA(isA<SqliteException>()),
    );
  });
}
