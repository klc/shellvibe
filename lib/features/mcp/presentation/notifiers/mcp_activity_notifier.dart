import 'dart:async';
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../data/mcp_providers.dart';
import '../../data/mcp_session_pool.dart';
import '../../data/repositories/mcp_repository_providers.dart';
import '../../domain/services/approval_coordinator.dart';
import '../../domain/services/mcp_service_providers.dart';

part 'mcp_activity_notifier.g.dart';

/// Best-effort, human-readable summary of one audit row's redacted
/// `argsJson`, for the activity panel and the audit screen alike.
///
/// This is display sugar only — it never re-derives a security decision, and
/// it never sees anything the [OutputRedactor]-scrubbed `args` blob didn't
/// already have redacted out of it. `run_command`'s `command` field is by far
/// the most common shape and is shown verbatim; everything else falls back to
/// a compact `key=value` join so a new tool never renders as a blank row.
String summarizeMcpAuditArgs(String argsJson) {
  try {
    final decoded = jsonDecode(argsJson);
    if (decoded is Map<String, Object?>) {
      final command = decoded['command'];
      if (command is String && command.isNotEmpty) return command;
      if (decoded.isEmpty) return '(no arguments)';
      return decoded.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(' ');
    }
  } catch (_) {
    // Fall through to the raw string below — a malformed blob is still worth
    // showing rather than hiding, since this is an audit surface.
  }
  return argsJson;
}

/// One row in a client's live timeline: either something the policy engine
/// already decided (an [McpAuditLogData] entry) or something still waiting on
/// a human ([PendingCommandApproval]). Modeled as one sealed hierarchy so the
/// panel can render both in a single time-ordered list instead of stitching
/// two lists together itself.
sealed class McpActivityRow {
  const McpActivityRow();

  DateTime get at;
}

final class McpActivityAuditRow extends McpActivityRow {
  final McpAuditLogData entry;

  const McpActivityAuditRow(this.entry);

  @override
  DateTime get at => entry.at;
}

final class McpActivityPendingRow extends McpActivityRow {
  final PendingCommandApproval pending;

  const McpActivityPendingRow(this.pending);

  @override
  DateTime get at => pending.requestedAt;
}

/// One connected client's live picture: its open sessions, what it currently
/// holds (grants, remembered approvals), what it is waiting on right now, and
/// a recent tail of what it already did.
///
/// Only clients that currently hold at least one open [McpSession] are
/// surfaced here — a registered-but-idle client belongs to the Settings
/// client list (owned by `McpSettingsNotifier`), not to a panel whose entire
/// point is "what is the agent doing right now".
final class McpClientActivity {
  final McpClient client;
  final List<McpSession> sessions;
  final List<McpHostGrant> activeGrants;
  final List<McpApproval> rememberedApprovals;
  final List<McpAuditLogData> recentAudit;
  final List<PendingCommandApproval> pendingApprovals;

  /// `hostId` -> display label, resolved once per refresh for every host
  /// referenced by [activeGrants] or [rememberedApprovals] (neither table
  /// stores a label of its own — see their table comments in
  /// `shared/database/tables.dart`). Audit rows don't need this map: they
  /// already carry their own denormalized `hostLabel`.
  final Map<String, String> hostLabels;

  const McpClientActivity({
    required this.client,
    required this.sessions,
    required this.activeGrants,
    required this.rememberedApprovals,
    required this.recentAudit,
    required this.pendingApprovals,
    required this.hostLabels,
  });

  /// Distinct hosts this client currently holds a live grant on — the
  /// panel's "N hosts" figure.
  int get grantedHostCount => activeGrants.map((g) => g.hostId).toSet().length;

  String hostLabelFor(String hostId) => hostLabels[hostId] ?? hostId;

  /// Pending approvals and completed audit rows merged into one
  /// newest-first timeline.
  List<McpActivityRow> get timeline {
    final rows = <McpActivityRow>[
      for (final pending in pendingApprovals) McpActivityPendingRow(pending),
      for (final entry in recentAudit) McpActivityAuditRow(entry),
    ];
    rows.sort((a, b) => b.at.compareTo(a.at));
    return rows;
  }
}

/// The AI Activity panel's entire live view, for one workspace.
final class McpActivityState {
  final List<McpClientActivity> clients;

  const McpActivityState({required this.clients});

  static const empty = McpActivityState(clients: []);
}

/// How many recent audit rows are pulled per connected client. The panel only
/// ever renders a handful of the newest ones — see `McpActivityPanel` — this
/// just needs enough headroom that a burst of activity doesn't cut off a row
/// still waiting to be paired with an in-flight approval.
const int _kRecentAuditRowsPerClient = 25;

/// Live view behind the AI Activity panel: connected clients, their open
/// sessions, what each one currently holds, what it is waiting on right now,
/// and a recent tail of what it already did.
///
/// This is deliberately a poll, not a cache. The four repositories underneath
/// it (`McpAuditRepository`, `McpGrantRepository`, `McpApprovalRepository`,
/// `McpClientRepository`) and the session pool have no shared change stream
/// of their own — every write happens deep in a tool handler with no
/// `BuildContext` anywhere near it — so the only way to stay honest about
/// "what is the agent doing right now" is to keep re-reading them. The panel
/// is the product's whole answer to "the agent is a black box in every other
/// tool"; a notifier that quietly went stale would undercut that promise more
/// than the extra queries cost.
@riverpod
class McpActivityNotifier extends _$McpActivityNotifier {
  Timer? _pollTimer;
  StreamSubscription<List<PendingCommandApproval>>? _pendingSub;

  @override
  Future<McpActivityState> build() async {
    final workspaceId = ref.watch(activeWorkspaceIdProvider);

    // Two independent triggers for a re-read: a fixed short poll (so grant
    // expiry, cooldowns and freshly-recorded audit rows show up even when
    // nothing else changed) and an immediate refresh the instant the
    // coordinator's pending-approval set changes (so "awaiting approval"
    // appears the moment the agent asks, not up to 3s later).
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refresh()),
    );
    ref.onDispose(() {
      _pollTimer?.cancel();
      _pollTimer = null;
    });

    final coordinator = ref.watch(approvalCoordinatorProvider);
    unawaited(_pendingSub?.cancel());
    _pendingSub = coordinator.pendingCommands.listen(
      (_) => unawaited(_refresh()),
    );
    ref.onDispose(() {
      unawaited(_pendingSub?.cancel());
      _pendingSub = null;
    });

    return _load(workspaceId);
  }

  /// Revokes one (client, host) grant and refreshes immediately, so the
  /// "Manage" list the user just acted on reflects the change without
  /// waiting for the next poll tick.
  Future<void> revokeGrant({
    required String clientId,
    required String hostId,
  }) async {
    await ref
        .read(mcpGrantRepositoryProvider)
        .revoke(clientId: clientId, hostId: hostId);
    await _refresh();
  }

  /// Revokes one remembered command approval and refreshes immediately.
  Future<void> revokeApproval(String approvalId) async {
    await ref.read(mcpApprovalRepositoryProvider).revoke(approvalId);
    await _refresh();
  }

  Future<void> _refresh() async {
    if (!ref.mounted) return;
    try {
      final workspaceId = ref.read(activeWorkspaceIdProvider);
      final next = await _load(workspaceId);
      if (ref.mounted) state = AsyncData(next);
    } catch (_) {
      // A transient failure on a background poll tick must not flash an
      // error screen over a panel that may already be showing correctly —
      // the next tick tries again. A failure on the very first [build] is
      // not caught here and still surfaces as AsyncError normally.
    }
  }

  Future<McpActivityState> _load(String workspaceId) async {
    final clientRepo = ref.read(mcpClientRepositoryProvider);
    final approvalRepo = ref.read(mcpApprovalRepositoryProvider);
    final auditRepo = ref.read(mcpAuditRepositoryProvider);
    final dao = ref.read(mcpDaoProvider);
    final pool = ref.read(mcpSessionPoolProvider);
    final coordinator = ref.read(approvalCoordinatorProvider);
    final hostsRepo = ref.read(hostsRepositoryProvider);

    final clients = await clientRepo.listClients(workspaceId);
    final pendingCommands = coordinator.currentCommands;
    final now = DateTime.now().toUtc();

    final activities = <McpClientActivity>[];
    for (final client in clients) {
      final sessions = pool.sessionsForClient(client.id);
      // Only a connected client (one holding an open session right now)
      // belongs on this panel — see [McpClientActivity]'s docstring.
      if (sessions.isEmpty) continue;

      // McpGrantRepository exposes no "list grants for a client" method —
      // only single-pair reads/writes and the panic-button bulk deletes (see
      // its docstring). Reading the DAO directly here, the same DAO the
      // repository itself wraps, is the pragmatic path rather than widening
      // that repository's fixed API for this one caller. The
      // expiresAt/cooldownUntil filtering below mirrors exactly what
      // `McpGrantRepository.effectiveMode` already does per-pair, just
      // applied across a whole list.
      final grants = await dao.getGrantsForClient(client.id);
      final activeGrants = grants.where((g) {
        if (g.expiresAt != null && !g.expiresAt!.isAfter(now)) return false;
        if (g.cooldownUntil != null && g.cooldownUntil!.isAfter(now)) {
          return false;
        }
        return true;
      }).toList();

      final approvals = await approvalRepo.listActive(client.id);
      final recentAudit = await auditRepo.query(
        clientId: client.id,
        limit: _kRecentAuditRowsPerClient,
      );
      final pendingForClient = pendingCommands
          .where((p) => p.request.clientId == client.id)
          .toList();

      final hostIds = {
        for (final grant in activeGrants) grant.hostId,
        for (final approval in approvals) approval.hostId,
      };
      final hostLabels = <String, String>{};
      for (final hostId in hostIds) {
        final host = await hostsRepo.getHostById(hostId);
        hostLabels[hostId] = host?.label ?? hostId;
      }

      activities.add(
        McpClientActivity(
          client: client,
          sessions: sessions,
          activeGrants: activeGrants,
          rememberedApprovals: approvals,
          recentAudit: recentAudit,
          pendingApprovals: pendingForClient,
          hostLabels: hostLabels,
        ),
      );
    }

    return McpActivityState(clients: activities);
  }
}
