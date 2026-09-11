import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'mcp_dao.g.dart';

@DriftAccessor(
  tables: [
    McpClients,
    McpHostGrants,
    McpPolicyRules,
    McpApprovals,
    McpAuditLog,
  ],
)
class McpDao extends DatabaseAccessor<AppDatabase> with _$McpDaoMixin {
  McpDao(super.db);

  // --- Clients ---

  Future<McpClient?> getClientById(String id) {
    return (select(
      mcpClients,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<List<McpClient>> getClientsByWorkspace(String workspaceId) {
    return (select(
      mcpClients,
    )..where((t) => t.workspaceId.equals(workspaceId))).get();
  }

  Future<int> insertClient(McpClientsCompanion client) =>
      into(mcpClients).insert(client);

  Future<int> updateClientLastSeen(String id, DateTime at) {
    return (update(mcpClients)..where((t) => t.id.equals(id))).write(
      McpClientsCompanion(lastSeenAt: Value(at)),
    );
  }

  Future<int> revokeClient(String id, DateTime at) {
    return (update(mcpClients)..where((t) => t.id.equals(id))).write(
      McpClientsCompanion(revokedAt: Value(at)),
    );
  }

  Future<int> deleteClient(String id) {
    return (delete(mcpClients)..where((t) => t.id.equals(id))).go();
  }

  /// Clients that can still authenticate: not revoked, and either permanent
  /// or not yet past [McpClients.expiresAt].
  Future<List<McpClient>> getAllActiveClients() {
    final now = DateTime.now();
    return (select(mcpClients)..where(
          (t) =>
              t.revokedAt.isNull() &
              (t.expiresAt.isNull() | t.expiresAt.isBiggerThanValue(now)),
        ))
        .get();
  }

  // --- Host grants ---

  Future<McpHostGrant?> findGrant(String clientId, String hostId) {
    return (select(mcpHostGrants)
          ..where((t) => t.clientId.equals(clientId) & t.hostId.equals(hostId)))
        .getSingleOrNull();
  }

  Future<List<McpHostGrant>> getGrantsForClient(String clientId) {
    return (select(
      mcpHostGrants,
    )..where((t) => t.clientId.equals(clientId))).get();
  }

  /// Updates the existing (client, host) grant if one exists, otherwise
  /// inserts a new row.
  ///
  /// [McpHostGrants] has no unique constraint on (clientId, hostId) — a row
  /// is looked up via [findGrant] first so that a user re-approving access
  /// after a revoke reuses the existing id (and whatever else may reference
  /// it) instead of accumulating duplicate grant rows for the same pair.
  Future<int> upsertGrant(McpHostGrantsCompanion grant) async {
    assert(
      grant.clientId.present && grant.hostId.present,
      'upsertGrant requires clientId and hostId to look up the existing row',
    );
    final existing = await findGrant(grant.clientId.value, grant.hostId.value);
    if (existing == null) {
      return into(mcpHostGrants).insert(grant);
    }
    return (update(
      mcpHostGrants,
    )..where((t) => t.id.equals(existing.id))).write(grant);
  }

  Future<int> deleteGrant(String id) {
    return (delete(mcpHostGrants)..where((t) => t.id.equals(id))).go();
  }

  Future<int> deleteGrantsForClient(String clientId) {
    return (delete(
      mcpHostGrants,
    )..where((t) => t.clientId.equals(clientId))).go();
  }

  /// Drops every "this session" grant scoped to a dropped MCP connection.
  Future<int> deleteGrantsByConnectionScope(String connectionScopeId) {
    return (delete(
      mcpHostGrants,
    )..where((t) => t.connectionScopeId.equals(connectionScopeId))).go();
  }

  Future<int> setGrantCooldown(String clientId, String hostId, DateTime until) {
    return (update(mcpHostGrants)
          ..where((t) => t.clientId.equals(clientId) & t.hostId.equals(hostId)))
        .write(McpHostGrantsCompanion(cooldownUntil: Value(until)));
  }

  /// Drops every grant, regardless of client or host. Used by the panic
  /// button, which revokes all agent access in one shot.
  Future<int> deleteAllGrants() => delete(mcpHostGrants).go();

  // --- Policy rules ---

  Future<List<McpPolicyRule>> getPolicyRulesForWorkspace(String workspaceId) {
    return (select(mcpPolicyRules)
          ..where((t) => t.workspaceId.equals(workspaceId))
          ..orderBy([(t) => OrderingTerm.asc(t.priority)]))
        .get();
  }

  Future<int> insertPolicyRule(McpPolicyRulesCompanion rule) =>
      into(mcpPolicyRules).insert(rule);

  Future<int> updatePolicyRule(String id, McpPolicyRulesCompanion rule) {
    return (update(mcpPolicyRules)..where((t) => t.id.equals(id))).write(rule);
  }

  Future<int> deletePolicyRule(String id) {
    return (delete(mcpPolicyRules)..where((t) => t.id.equals(id))).go();
  }

  // --- Approvals ---

  Future<McpApproval?> findApproval(
    String clientId,
    String hostId,
    String cwd,
    String commandSha256,
  ) {
    return (select(mcpApprovals)..where(
          (t) =>
              t.clientId.equals(clientId) &
              t.hostId.equals(hostId) &
              t.cwd.equals(cwd) &
              t.commandSha256.equals(commandSha256),
        ))
        .getSingleOrNull();
  }

  Future<int> insertApproval(McpApprovalsCompanion approval) =>
      into(mcpApprovals).insert(approval);

  /// Drops approvals past [McpApprovals.expiresAt]. Rows with a null
  /// `expiresAt` ("her zaman") are permanent and never match here — SQL NULL
  /// comparisons are false, so they are skipped without an explicit check.
  Future<int> deleteExpiredApprovals(DateTime now) {
    return (delete(
      mcpApprovals,
    )..where((t) => t.expiresAt.isSmallerThanValue(now))).go();
  }

  Future<int> deleteApprovalsByConnectionScope(String connectionScopeId) {
    return (delete(
      mcpApprovals,
    )..where((t) => t.connectionScopeId.equals(connectionScopeId))).go();
  }

  /// Drops every remembered approval. Used by the panic button.
  Future<int> deleteAllApprovals() => delete(mcpApprovals).go();

  Future<List<McpApproval>> getActiveApprovals(String clientId) {
    final now = DateTime.now();
    return (select(mcpApprovals)..where(
          (t) =>
              t.clientId.equals(clientId) &
              (t.expiresAt.isNull() | t.expiresAt.isBiggerThanValue(now)),
        ))
        .get();
  }

  // --- Audit log ---

  Future<int> insertAuditEntry(McpAuditLogCompanion entry) =>
      into(mcpAuditLog).insert(entry);

  /// Filters are ANDed together; any left null is not applied. Newest first.
  Future<List<McpAuditLogData>> queryEntries({
    String? clientId,
    String? hostId,
    String? decision,
    String? category,
    DateTime? from,
    DateTime? to,
    int? limit,
    int? offset,
  }) {
    final query = select(mcpAuditLog)
      ..orderBy([(t) => OrderingTerm.desc(t.at)]);
    if (clientId != null) {
      query.where((t) => t.clientId.equals(clientId));
    }
    if (hostId != null) {
      query.where((t) => t.hostId.equals(hostId));
    }
    if (decision != null) {
      query.where((t) => t.decision.equals(decision));
    }
    if (category != null) {
      query.where((t) => t.category.equals(category));
    }
    if (from != null) {
      query.where((t) => t.at.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where((t) => t.at.isSmallerOrEqualValue(to));
    }
    if (limit != null) {
      query.limit(limit, offset: offset);
    }
    return query.get();
  }

  /// The audit log is retained on a rolling window (default 90 days,
  /// see the settings screen); rows are never edited, only aged out.
  Future<int> deleteOlderThan(DateTime cutoff) {
    return (delete(
      mcpAuditLog,
    )..where((t) => t.at.isSmallerThanValue(cutoff))).go();
  }
}
