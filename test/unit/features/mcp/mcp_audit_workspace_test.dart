import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/features/mcp/data/repositories/mcp_audit_repository.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/shared/database/app_database.dart';

/// The audit log is read one workspace at a time.
void main() {
  late AppDatabase db;
  late McpAuditRepository audit;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    audit = McpAuditRepository(db.mcpDao);
    for (final ws in ['ws-a', 'ws-b']) {
      await audit.record(
        clientId: 'client-$ws',
        clientName: 'Agent',
        workspaceId: ws,
        tool: 'run_command',
        args: {'command': 'echo $ws'},
        decision: AuditDecision.allowed,
      );
    }
    // A pre-v22 row that no host could place.
    await db.mcpDao.insertAuditEntry(
      McpAuditLogCompanion.insert(
        id: 'legacy',
        at: DateTime.utc(2026),
        clientId: 'gone',
        clientName: 'Agent',
        tool: 'run_runbook',
        argsJson: '{}',
        decision: 'allowed',
      ),
    );
  });

  tearDown(() => db.close());

  test('a workspace sees its own rows and unplaced ones, not others', () async {
    final rows = await audit.query(workspaceId: 'ws-a');
    expect(rows.map((r) => r.id), hasLength(2));
    expect(rows.map((r) => r.workspaceId), unorderedEquals(['ws-a', null]));

    final csv = await audit.exportCsv(workspaceId: 'ws-a');
    expect(csv, contains('echo ws-a'));
    expect(csv, isNot(contains('echo ws-b')));

    final json = await audit.exportJson(workspaceId: 'ws-a');
    expect(json, isNot(contains('echo ws-b')));
  });

  test('no workspace filter still returns everything', () async {
    expect(await audit.query(), hasLength(3));
  });
}
