import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/mcp_dao.dart';
import '../../domain/models/mcp_enums.dart';

/// Database boundary for the MCP audit log.
///
/// Every row is written once and never edited — [purgeOlderThan] is the only
/// sanctioned way rows disappear, and that is a retention sweep, not an
/// edit. `clientId`/`hostId` are deliberately NOT foreign keys to
/// `McpClients`/`Hosts` (see the table comment in
/// `shared/database/tables.dart`): `clientName`/`hostLabel` are copied in at
/// write time, so revoking a client or deleting a host later cannot erase or
/// blank the history of what that client or host did. A denied or errored
/// call is recorded exactly like an allowed one — the log's value is in what
/// was *attempted*, not only in what succeeded.
class McpAuditRepository {
  final McpDao dao;

  const McpAuditRepository(this.dao);

  /// Default retention window, matching the Settings screen's default.
  static const defaultRetention = Duration(days: 90);

  static const _exportRowCap = 100000;

  /// Records one tool call.
  ///
  /// [args] is JSON-encoded here exactly as given — it must already have
  /// passed through the redaction layer before this call is made. That is a
  /// deliberate one-way door: this repository stores whatever it is handed
  /// and performs no masking of its own, so there is exactly one place in
  /// the codebase (`OutputRedactor`) that decides what a secret looks like,
  /// instead of two definitions of "secret" that can quietly drift apart.
  Future<void> record({
    required String clientId,
    required String clientName,
    String? hostId,
    String? hostLabel,
    required String tool,
    required Map<String, Object?> args,
    required AuditDecision decision,
    RiskCategory? category,
    int? exitCode,
    int? durationMs,
    int? outputBytes,
    String? outputSha256,
  }) async {
    await dao.insertAuditEntry(
      McpAuditLogCompanion.insert(
        id: const Uuid().v4(),
        at: DateTime.now().toUtc(),
        clientId: clientId,
        clientName: clientName,
        hostId: Value(hostId),
        hostLabel: Value(hostLabel),
        tool: tool,
        argsJson: jsonEncode(args),
        decision: decision.wireName,
        category: Value(category?.wireName),
        exitCode: Value(exitCode),
        durationMs: Value(durationMs),
        outputBytes: Value(outputBytes),
        outputSha256: Value(outputSha256),
      ),
    );
  }

  /// Queries audit rows, newest first. Every filter left null is not
  /// applied; filters are ANDed together.
  Future<List<McpAuditLogData>> query({
    String? clientId,
    String? hostId,
    AuditDecision? decision,
    RiskCategory? category,
    DateTime? from,
    DateTime? to,
    int limit = 200,
    int offset = 0,
  }) {
    return dao.queryEntries(
      clientId: clientId,
      hostId: hostId,
      decision: decision?.wireName,
      category: category?.wireName,
      from: from,
      to: to,
      limit: limit,
      offset: offset,
    );
  }

  /// Deletes rows older than [retention] (default 90 days). The caller
  /// passes whatever retention the user actually configured in Settings —
  /// this repository does not read that setting itself, only applies the
  /// duration it is given.
  Future<int> purgeOlderThan([Duration retention = defaultRetention]) {
    final cutoff = DateTime.now().toUtc().subtract(retention);
    return dao.deleteOlderThan(cutoff);
  }

  /// Exports matching rows as a JSON array string, for the audit screen's
  /// "export" action. Filters have the same meaning as [query]; export is
  /// capped at [_exportRowCap] rows so an unbounded date range can't hang
  /// the UI thread building a multi-million-row string.
  Future<String> exportJson({
    String? clientId,
    String? hostId,
    AuditDecision? decision,
    RiskCategory? category,
    DateTime? from,
    DateTime? to,
  }) async {
    final rows = await query(
      clientId: clientId,
      hostId: hostId,
      decision: decision,
      category: category,
      from: from,
      to: to,
      limit: _exportRowCap,
      offset: 0,
    );
    return jsonEncode(rows.map(_rowToJson).toList());
  }

  /// Exports matching rows as CSV text, for the audit screen's "export"
  /// action. Same filters and row cap as [exportJson].
  Future<String> exportCsv({
    String? clientId,
    String? hostId,
    AuditDecision? decision,
    RiskCategory? category,
    DateTime? from,
    DateTime? to,
  }) async {
    final rows = await query(
      clientId: clientId,
      hostId: hostId,
      decision: decision,
      category: category,
      from: from,
      to: to,
      limit: _exportRowCap,
      offset: 0,
    );
    final buffer = StringBuffer()..writeln(_csvRow(_csvHeader));
    for (final row in rows) {
      buffer.writeln(_csvRow(_csvFields(row)));
    }
    return buffer.toString();
  }

  static const _csvHeader = [
    'id',
    'at',
    'clientId',
    'clientName',
    'hostId',
    'hostLabel',
    'tool',
    'args',
    'decision',
    'category',
    'exitCode',
    'durationMs',
    'outputBytes',
    'outputSha256',
  ];

  List<String> _csvFields(McpAuditLogData row) => [
    row.id,
    row.at.toIso8601String(),
    row.clientId,
    row.clientName,
    row.hostId ?? '',
    row.hostLabel ?? '',
    row.tool,
    row.argsJson,
    row.decision,
    row.category ?? '',
    row.exitCode?.toString() ?? '',
    row.durationMs?.toString() ?? '',
    row.outputBytes?.toString() ?? '',
    row.outputSha256 ?? '',
  ];

  Map<String, Object?> _rowToJson(McpAuditLogData row) => {
    'id': row.id,
    'at': row.at.toIso8601String(),
    'clientId': row.clientId,
    'clientName': row.clientName,
    'hostId': row.hostId,
    'hostLabel': row.hostLabel,
    'tool': row.tool,
    'args': jsonDecode(row.argsJson),
    'decision': row.decision,
    'category': row.category,
    'exitCode': row.exitCode,
    'durationMs': row.durationMs,
    'outputBytes': row.outputBytes,
    'outputSha256': row.outputSha256,
  };

  /// Quotes one CSV row: every field is wrapped in double quotes and
  /// internal quotes are doubled (RFC 4180), which is sufficient to survive
  /// the commas, quotes and newlines that routinely show up in shell
  /// commands and their output without pulling in a CSV dependency for it.
  String _csvRow(List<String> fields) {
    return fields.map((f) => '"${f.replaceAll('"', '""')}"').join(',');
  }
}
