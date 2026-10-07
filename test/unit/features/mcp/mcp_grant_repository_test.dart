import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/features/mcp/data/repositories/mcp_grant_repository.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/shared/database/app_database.dart';

/// Unit tests for [McpGrantRepository]'s denial cooldown.
void main() {
  late AppDatabase db;
  late McpGrantRepository grants;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    grants = McpGrantRepository(db.mcpDao);
    await db.hostsDao.insertHost(
      HostsCompanion.insert(
        id: 'host-1',
        workspaceId: 'default',
        label: 'Host 1',
        hostname: '10.0.0.1',
        createdAt: DateTime.now(),
      ),
    );
    await db.mcpDao.insertClient(
      McpClientsCompanion.insert(
        id: 'client-1',
        workspaceId: 'default',
        name: 'Agent',
        tokenHash: 'hash-1',
        createdAt: DateTime.now(),
      ),
    );
  });

  tearDown(() => db.close());

  DateTime inMinutes(int m) => DateTime.now().toUtc().add(Duration(minutes: m));

  test('a denial for a never-granted pair never becomes a grant', () async {
    await grants.denyWithCooldown(clientId: 'client-1', hostId: 'host-1');

    expect(
      await grants.effectiveMode('client-1', 'host-1', now: inMinutes(5)),
      isNull,
    );
    expect(
      await grants.effectiveMode('client-1', 'host-1', now: inMinutes(11)),
      isNull,
    );
    expect(
      await grants.effectiveMode('client-1', 'host-1', now: inMinutes(60 * 24)),
      isNull,
    );
  });

  test('a later approval replaces the denial placeholder', () async {
    await grants.denyWithCooldown(clientId: 'client-1', hostId: 'host-1');
    await grants.grant(
      clientId: 'client-1',
      hostId: 'host-1',
      mode: McpAccessMode.guarded,
    );

    expect(
      await grants.effectiveMode('client-1', 'host-1'),
      McpAccessMode.guarded,
    );
  });

  test('denying an existing grant only pauses it for the cooldown', () async {
    await grants.grant(
      clientId: 'client-1',
      hostId: 'host-1',
      mode: McpAccessMode.readonly,
    );
    await grants.denyWithCooldown(clientId: 'client-1', hostId: 'host-1');

    expect(
      await grants.effectiveMode('client-1', 'host-1', now: inMinutes(5)),
      isNull,
    );
    expect(
      await grants.effectiveMode('client-1', 'host-1', now: inMinutes(11)),
      McpAccessMode.readonly,
    );
  });
}
