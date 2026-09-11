import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/mcp_dao.dart';
import '../../domain/models/mcp_enums.dart';

/// Database boundary for (client x host) access grants.
///
/// A grant is the stored answer to `request_host_access`: which
/// [McpAccessMode] a client may use on a host, until when, and whether it is
/// scoped to one MCP connection ("this session"). Expiry and cooldown are
/// always evaluated against a caller-supplied `now` rather than an internal
/// `DateTime.now()` call, so the time-dependent branches here can be
/// exercised deterministically in tests.
class McpGrantRepository {
  final McpDao dao;

  const McpGrantRepository(this.dao);

  /// The mode a client currently holds on a host, or null if it holds none
  /// usable right now.
  ///
  /// Null deliberately covers three distinct database states: no grant row
  /// at all, a grant whose [McpHostGrant.expiresAt] has passed, and a grant
  /// still inside its [McpHostGrant.cooldownUntil] window after a prior
  /// denial. Every caller only needs "may this client proceed on this host",
  /// so collapsing those three into one null keeps the policy engine from
  /// having to know about cooldowns and expiry as separate concepts.
  Future<McpAccessMode?> effectiveMode(
    String clientId,
    String hostId, {
    DateTime? now,
  }) async {
    final grant = await dao.findGrant(clientId, hostId);
    if (grant == null) return null;
    final at = now ?? DateTime.now().toUtc();
    if (grant.expiresAt != null && !grant.expiresAt!.isAfter(at)) return null;
    if (grant.cooldownUntil != null && grant.cooldownUntil!.isAfter(at)) {
      return null;
    }
    return McpAccessMode.fromName(grant.mode);
  }

  /// Grants or updates (client, host) access.
  ///
  /// Looks up any existing row for this pair first so a re-approval reuses
  /// its id instead of piling up duplicate grant rows for the same pair —
  /// the same intent as [McpDao.upsertGrant]'s own lookup, resolved here so
  /// the id is stable regardless of that method's write() field-presence
  /// semantics. A fresh grant also clears any prior [McpHostGrant.cooldownUntil]:
  /// granting access is a deliberate reversal of an earlier denial, and a
  /// stale cooldown should not silently keep shadowing it.
  Future<void> grant({
    required String clientId,
    required String hostId,
    required McpAccessMode mode,
    DateTime? expiresAt,
    String? connectionScopeId,
  }) async {
    final existing = await dao.findGrant(clientId, hostId);
    await dao.upsertGrant(
      McpHostGrantsCompanion.insert(
        id: existing?.id ?? const Uuid().v4(),
        clientId: clientId,
        hostId: hostId,
        mode: mode.name,
        grantedAt: DateTime.now().toUtc(),
        expiresAt: Value(expiresAt),
        connectionScopeId: Value(connectionScopeId),
        cooldownUntil: const Value(null),
      ),
    );
  }

  /// Marks (client, host) as refused until [cooldown] has passed.
  ///
  /// This cooldown is the one mechanism standing between a looping agent and
  /// a user buried in approval windows: every `request_host_access` call for
  /// this exact pair inside the window is refused silently — no dialog shown
  /// at all — until it lapses.
  Future<void> denyWithCooldown({
    required String clientId,
    required String hostId,
    Duration cooldown = const Duration(minutes: 10),
  }) async {
    final until = DateTime.now().toUtc().add(cooldown);
    final existing = await dao.findGrant(clientId, hostId);
    if (existing == null) {
      // No grant has ever existed for this pair: create a cooldown-only
      // placeholder row so the next request still sees the cooldown. `mode`
      // is meaningless while there is no real grant; readonly is the
      // least-privileged filler value.
      await dao.upsertGrant(
        McpHostGrantsCompanion.insert(
          id: const Uuid().v4(),
          clientId: clientId,
          hostId: hostId,
          mode: McpAccessMode.readonly.name,
          grantedAt: DateTime.now().toUtc(),
          cooldownUntil: Value(until),
        ),
      );
    } else {
      await dao.setGrantCooldown(clientId, hostId, until);
    }
  }

  /// Revokes one (client, host) grant, if it exists.
  Future<void> revoke({
    required String clientId,
    required String hostId,
  }) async {
    final existing = await dao.findGrant(clientId, hostId);
    if (existing != null) {
      await dao.deleteGrant(existing.id);
    }
  }

  /// Revokes every grant a client holds, e.g. when the client itself is
  /// deleted.
  Future<void> revokeAllForClient(String clientId) =>
      dao.deleteGrantsForClient(clientId);

  /// Drops every "this session" grant scoped to a dropped MCP connection.
  Future<void> revokeByConnectionScope(String connectionScopeId) =>
      dao.deleteGrantsByConnectionScope(connectionScopeId);

  /// The panic button: drops every grant for every client on every host.
  /// Deliberately unconditional — no dialog, no partial revoke.
  Future<void> revokeEverything() => dao.deleteAllGrants();
}
