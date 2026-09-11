import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../../core/mcp/mcp_token.dart';
import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/mcp_dao.dart';

/// Database boundary for MCP client registration and authentication.
///
/// A "client" here is one registered agent install (e.g. one Claude Desktop
/// or Claude Code instance), identified by a bearer token the user copies
/// into that agent's config once. Only [McpToken.hash] of the token is ever
/// persisted — see `core/mcp/mcp_token.dart` for why SHA-256 rather than
/// Argon2id is the correct tool for a secret that is 32 bytes of CSPRNG
/// output and gets checked on every JSON-RPC request.
class McpClientRepository {
  final McpDao dao;

  const McpClientRepository(this.dao);

  /// Default token lifetime when the caller does not specify one.
  ///
  /// 30 days balances "the user should not have to regenerate on every
  /// visit" against "a token copied into a config file and forgotten should
  /// not stay valid forever".
  static const defaultValidity = Duration(days: 30);

  /// Registers a new client and returns its id and the raw bearer token.
  ///
  /// This is the ONLY moment the raw token exists outside the agent's own
  /// config: the database receives [McpToken.hash] of it, never the token
  /// itself. The caller is responsible for showing [rawToken] to the user
  /// exactly once (typically inside the copyable JSON block in Settings)
  /// and then discarding its own copy — nothing below this call can recover
  /// it again.
  Future<(String clientId, String rawToken)> createClient({
    required String workspaceId,
    required String name,
    Duration? validFor,
  }) async {
    final id = const Uuid().v4();
    final rawToken = McpToken.generate();
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(validFor ?? defaultValidity);
    await dao.insertClient(
      McpClientsCompanion.insert(
        id: id,
        workspaceId: workspaceId,
        name: name,
        tokenHash: McpToken.hash(rawToken),
        createdAt: now,
        expiresAt: Value(expiresAt),
      ),
    );
    return (id, rawToken);
  }

  /// Authenticates a bearer token presented by an agent on an incoming
  /// JSON-RPC request.
  ///
  /// Every currently-active client's hash is checked with [McpToken.verify],
  /// which compares in constant time — see `core/mcp/mcp_token.dart` for why
  /// that matters on a check that runs on every request rather than once per
  /// session. The revoked/expired guard below duplicates what
  /// [McpDao.getAllActiveClients] already filters for; that redundancy is
  /// deliberate. Authentication is the one place in this feature where a
  /// stale or accidentally loosened DAO query must fail *closed*, not open —
  /// a revoked token must never come back to life just because some later
  /// change relaxed that query's WHERE clause.
  Future<McpClient?> authenticate(String rawToken) async {
    final now = DateTime.now().toUtc();
    final candidates = await dao.getAllActiveClients();
    for (final client in candidates) {
      if (!McpToken.verify(rawToken, client.tokenHash)) continue;
      if (client.revokedAt != null) return null;
      if (client.expiresAt != null && !client.expiresAt!.isAfter(now)) {
        return null;
      }
      await dao.updateClientLastSeen(client.id, now);
      return client;
    }
    return null;
  }

  /// Revokes a client immediately. The row stays — so a subsequent
  /// authentication attempt with its old token fails cleanly and any audit
  /// history referencing it (by copied label, not foreign key) remains
  /// intact — only [McpClient.revokedAt] is set.
  Future<void> revokeClient(String id) =>
      dao.revokeClient(id, DateTime.now().toUtc());

  /// Deletes a client row outright, e.g. when the user removes it from
  /// Settings rather than merely revoking it.
  Future<void> deleteClient(String id) => dao.deleteClient(id);

  Future<List<McpClient>> listClients(String workspaceId) =>
      dao.getClientsByWorkspace(workspaceId);
}
