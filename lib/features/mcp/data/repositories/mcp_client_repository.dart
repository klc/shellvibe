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
    // 30 days balances "the user should not have to regenerate on every
    // visit" against "a token copied into a config file and forgotten should
    // not stay valid forever".
    final expiresAt = now.add(validFor ?? const Duration(days: 30));
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

  /// Returns a fresh raw token for the system client row named [name] in
  /// [workspaceId], creating the row if it does not exist yet.
  ///
  /// The row itself is kept, so the grants and "Always" approvals hanging
  /// off it survive a server restart; only its token changes. A revocation
  /// ("Deny and suspend client") survives too unless [reinstate] is set,
  /// which the user turning AI access on does. The token does not expire:
  /// it is rotated on every start anyway, and an expiry would only swap the
  /// identity under a long-running app.
  ///
  /// Rows of that name in other workspaces get a token nobody holds, so a
  /// bridge still holding an old one cannot reach a workspace the server no
  /// longer serves.
  Future<String> issueSystemToken({
    required String workspaceId,
    required String name,
    bool reinstate = false,
  }) async {
    String? issued;
    for (final client in await dao.getClientsNamed(name)) {
      final token = McpToken.generate();
      final mine = issued == null && client.workspaceId == workspaceId;
      await dao.replaceClientToken(
        client.id,
        McpToken.hash(token),
        reinstate: mine && reinstate,
      );
      if (mine) issued = token;
    }
    if (issued != null) return issued;

    final token = McpToken.generate();
    await dao.insertClient(
      McpClientsCompanion.insert(
        id: const Uuid().v4(),
        workspaceId: workspaceId,
        name: name,
        tokenHash: McpToken.hash(token),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    return token;
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

  /// Every client named [name] in any workspace.
  Future<List<McpClient>> listClientsNamed(String name) =>
      dao.getClientsNamed(name);

  /// True when [rawToken] belongs to a row the user revoked. Unlike
  /// [authenticate] this sees revoked rows: it exists so a deliberate
  /// revocation can be told apart from a row that simply went missing.
  Future<bool> isRevoked(String rawToken) async {
    final row = await dao.getClientByTokenHash(McpToken.hash(rawToken));
    return row?.revokedAt != null;
  }
}
