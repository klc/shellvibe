import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/mcp_dao.dart';
import '../../domain/models/mcp_enums.dart';

/// Database boundary for remembered command approvals.
///
/// A remembered approval is keyed to the exact tuple `(clientId, hostId,
/// cwd, normalizeCommand(command))` and is NEVER generalized into a pattern:
/// an approval the user gave for `rm -rf ./nginx/*.gz` in `/var/log` must
/// never authorize `rm -rf *` anywhere, and must not even cover the same
/// command text in a different directory. A user who wants pattern-based
/// auto-approval writes a policy rule themselves — the decision to
/// generalize belongs to a human, never to this repository.
class McpApprovalRepository {
  final McpDao dao;

  const McpApprovalRepository(this.dao);

  /// Collapses leading/trailing and repeated whitespace in [command].
  /// Nothing else.
  ///
  /// This is the ONLY normalization an approval's match key ever goes
  /// through. Anything smarter — stripping quotes, sorting flags, resolving
  /// `..` in paths, collapsing equivalent option spellings — would let one
  /// approval silently cover a command the user never actually saw and
  /// approved. Whitespace collapsing exists only so that incidental
  /// double-spaces from an agent's own formatting don't defeat a match the
  /// user clearly intended to cover.
  String normalizeCommand(String command) {
    return command.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Lowercase hex SHA-256 of [normalized], used as the DB lookup index
  /// (`McpApprovals.commandSha256`) so a match doesn't require indexing or
  /// comparing full, possibly-long command text.
  String commandSha256(String normalized) {
    final digest = const DartSha256().hashSync(utf8.encode(normalized));
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Whether an unexpired approval exists for the exact tuple `(clientId,
  /// hostId, cwd, normalizeCommand(command))`.
  ///
  /// This is never a pattern match: the presented command is normalized the
  /// same way a remembered one was, then compared for exact equality via its
  /// hash. A row past its [McpApproval.expiresAt] does not match — it is
  /// treated the same as if it had never been remembered.
  Future<bool> hasApproval({
    required String clientId,
    required String hostId,
    required String cwd,
    required String command,
    DateTime? now,
  }) async {
    final sha = commandSha256(normalizeCommand(command));
    final approval = await dao.findApproval(clientId, hostId, cwd, sha);
    if (approval == null) return false;
    final at = now ?? DateTime.now().toUtc();
    if (approval.expiresAt != null && !approval.expiresAt!.isAfter(at)) {
      return false;
    }
    return true;
  }

  /// Remembers a command approval for [scope]. No-ops for [ApprovalScope.once].
  ///
  /// - `once` stores nothing at all — there is nothing to remember; the
  ///   approval only ever applied to the single call that just ran.
  /// - `fifteenMinutes` -> row expires at `now + 15m`.
  /// - `session` -> no expiry, but tagged with [connectionScopeId] so it is
  ///   dropped the moment that MCP connection drops.
  /// - `always` -> no expiry and no connection tag: a durable rule that
  ///   survives reconnects and only a user cancelling it removes.
  Future<void> remember({
    required String clientId,
    required String hostId,
    required String cwd,
    required String command,
    required ApprovalScope scope,
    String? connectionScopeId,
  }) async {
    DateTime? expiresAt;
    String? scopeTag;
    switch (scope) {
      case ApprovalScope.once:
        return;
      case ApprovalScope.fifteenMinutes:
        expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 15));
        break;
      case ApprovalScope.session:
        scopeTag = connectionScopeId;
        break;
      case ApprovalScope.always:
        break;
    }

    final normalized = normalizeCommand(command);
    await dao.insertApproval(
      McpApprovalsCompanion.insert(
        id: const Uuid().v4(),
        clientId: clientId,
        hostId: hostId,
        cwd: cwd,
        commandNormalized: normalized,
        commandSha256: commandSha256(normalized),
        approvedAt: DateTime.now().toUtc(),
        expiresAt: Value(expiresAt),
        connectionScopeId: Value(scopeTag),
      ),
    );
  }

  Future<List<McpApproval>> listActive(String clientId) =>
      dao.getActiveApprovals(clientId);

  /// Revokes one remembered approval by id, e.g. from the "cancel" action in
  /// the AI Activity panel's active-approvals list.
  ///
  /// [McpDao] intentionally exposes no single-row delete for approvals — its
  /// bulk methods cover the panic button, connection-scope cleanup and
  /// expiry sweeps, which are the shapes every other caller needs. A one-off
  /// "drop exactly this row" delete goes straight through drift's own table
  /// API here instead of growing the DAO's surface for a single caller.
  Future<void> revoke(String approvalId) async {
    await (dao.delete(
      dao.mcpApprovals,
    )..where((t) => t.id.equals(approvalId))).go();
  }

  /// Drops every remembered approval. Used by the panic button.
  Future<void> revokeAll() => dao.deleteAllApprovals();

  /// Sweeps rows past their [McpApproval.expiresAt]. Rows with a null expiry
  /// (`session` or `always` scope) are untouched.
  Future<void> purgeExpired() =>
      dao.deleteExpiredApprovals(DateTime.now().toUtc());
}
