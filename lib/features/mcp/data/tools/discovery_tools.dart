import '../../../../core/mcp/mcp_protocol.dart';
import '../../../../shared/database/app_database.dart' show Host;
import '../../../../shared/database/daos/hosts_dao.dart';
import '../../../../shared/database/daos/workspaces_dao.dart';
import '../../../hosts/data/repositories/hosts_repository.dart';
import '../../domain/models/mcp_enums.dart';
import '../../domain/models/mcp_models.dart';
import '../../domain/services/approval_coordinator.dart';
import '../../domain/services/output_redactor.dart';
import '../repositories/mcp_audit_repository.dart';
import '../repositories/mcp_grant_repository.dart';
import 'mcp_tool_handler.dart';

/// Reads the MCP-specific `Hosts` columns (`mcpVisible`, and `mcpDefaultMode`,
/// which holds the host's max access) directly off [HostsDao]. Every discovery
/// tool below still goes through [HostsRepository] first for the fields it
/// needs (label, hostname, port, groups, jump host); this helper only fills
/// the gap, by id, straight from the DAO both share.
Future<Host?> _hostRow(HostsDao hostsDao, String hostId) =>
    hostsDao.getHostById(hostId);

bool _isMcpVisible(Host? row) => row == null || row.mcpVisible;

/// The most any grant on this host may allow.
McpAccessMode _maxModeOf(Host? row) => row == null
    ? McpAccessMode.readonly
    : McpAccessMode.fromName(row.mcpDefaultMode);

/// `list_hosts` — the agent's entire inventory of what it *could* ask to
/// reach.
///
/// The docstring below is load-bearing, not decorative: an agent reads it to
/// learn it can never obtain a hostname/port/credential to connect with
/// directly, only an opaque [Host.id] to hand to other tools. `tags[]` from
/// the plan's original draft is intentionally absent — `Hosts` has no tags
/// column, so `groups` (the names of the host's group tags) is exposed instead.
class ListHostsTool with McpArgReaders implements McpToolHandler {
  final HostsRepository hostsRepository;
  final HostsDao hostsDao;
  final McpGrantRepository grantRepository;
  final WorkspacesDao workspacesDao;

  const ListHostsTool({
    required this.hostsRepository,
    required this.hostsDao,
    required this.grantRepository,
    required this.workspacesDao,
  });

  @override
  String get name => 'list_hosts';

  @override
  McpToolDefinition get definition => McpToolDefinition(
    name: name,
    description:
        'Start here to run anything on a remote server over SSH. '
        'Lists every host registered in this client\'s workspace that is '
        'visible to MCP agents (a host owner can hide any host from agents '
        'entirely; hidden hosts never appear here). Returns '
        '{"workspace": {"id", "name"}, "hosts": [...]}. IMPORTANT: this '
        'token is bound to ONE workspace for its whole life, named in '
        '"workspace" — switching workspaces in the ShellVibe window does not '
        'change what this tool returns, and hosts saved in another workspace '
        'are never listed here. If the user asks for a host that is missing, '
        'tell them which workspace you can see and that the host may live in '
        'a different one, which this connection cannot see. For each host '
        'this reports its maxMode (the most any grant there can allow), '
        'whether the caller currently has access ("granted"/"none") and, if '
        'granted, the access mode. The '
        'hostId returned here is the ONLY handle any MCP tool ever gives you '
        'on a host: hostname, port, username, and credentials are never '
        'returned by this or any other tool. To act on a host, request access '
        'with request_host_access, then open_session with its hostId.',
    inputSchema: const {
      'type': 'object',
      'properties': <String, Object?>{},
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> execute(McpToolContext ctx, Map<String, Object?> args) async {
    final hosts = await hostsRepository.getHostsByWorkspace(ctx.workspaceId);
    final result = <Map<String, Object?>>[];

    for (final host in hosts) {
      final row = await _hostRow(hostsDao, host.id);
      if (!_isMcpVisible(row)) continue;

      final maxMode = _maxModeOf(row);
      final mode = (await grantRepository.effectiveMode(
        ctx.clientId,
        host.id,
        connectionScopeId: ctx.connectionScopeId,
      ))?.atMost(maxMode);
      final groupNames = await _groupNames(hostsRepository, host.groupIds);

      result.add({
        'id': host.id,
        'label': host.label,
        'maxMode': maxMode.name,
        'groups': groupNames,
        'access': mode == null ? 'none' : 'granted',
        'mode': mode?.name,
      });
    }

    // The workspace travels with the list rather than being left implicit.
    // A token is pinned to the workspace it was issued in, so an agent that
    // cannot find a host has no way to tell "it is hidden" from "it is in the
    // workspace next door" — and neither did the user, who saw the app
    // showing one workspace and the agent answering about another.
    final workspace = await workspacesDao.getWorkspaceById(ctx.workspaceId);
    return {
      'workspace': {
        'id': ctx.workspaceId,
        'name': workspace?.name ?? ctx.workspaceId,
      },
      'hosts': result,
    };
  }
}

/// Names of the groups behind [groupIds], sorted so the output is stable.
/// A group that vanished since the host was read is left out.
Future<List<String>> _groupNames(
  HostsRepository hostsRepository,
  List<String> groupIds,
) async {
  final names = <String>[];
  for (final id in groupIds) {
    final group = await hostsRepository.getHostGroupById(id);
    if (group != null) names.add(group.name);
  }
  return names..sort();
}

/// `describe_host` — detail on one host the agent already knows the id of
/// (from `list_hosts`).
class DescribeHostTool with McpArgReaders implements McpToolHandler {
  final HostsRepository hostsRepository;
  final HostsDao hostsDao;
  final McpGrantRepository grantRepository;

  const DescribeHostTool({
    required this.hostsRepository,
    required this.hostsDao,
    required this.grantRepository,
  });

  @override
  String get name => 'describe_host';

  @override
  McpToolDefinition get definition => McpToolDefinition(
    name: name,
    description:
        'Returns detail on one host by id, including the current access '
        'grant (if any) and, when the host is reached through another host, '
        'that jump host\'s label. As with list_hosts, no credential, '
        'username, or identity id is ever included — jumpHost is a label, '
        'not a connection target you can use directly.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'hostId': {
          'type': 'string',
          'description':
              'The opaque id of the host to describe, as returned by list_hosts.',
        },
      },
      'required': ['hostId'],
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> execute(McpToolContext ctx, Map<String, Object?> args) async {
    final hostId = requireString(args, 'hostId');
    final host = await hostsRepository.getHostById(hostId);
    if (host == null || host.workspaceId != ctx.workspaceId) {
      throw McpToolException(
        McpErrorCode.hostNotVisible,
        'No host with id "$hostId" is visible to this client.',
      );
    }

    final row = await _hostRow(hostsDao, hostId);
    if (!_isMcpVisible(row)) {
      throw McpToolException(
        McpErrorCode.hostNotVisible,
        'No host with id "$hostId" is visible to this client.',
      );
    }

    final groupNames = await _groupNames(hostsRepository, host.groupIds);
    final jumpLabel = host.jumpHostId == null
        ? null
        : (await hostsRepository.getHostById(host.jumpHostId!))?.label;
    final maxMode = _maxModeOf(row);
    final mode = (await grantRepository.effectiveMode(
      ctx.clientId,
      hostId,
      connectionScopeId: ctx.connectionScopeId,
    ))?.atMost(maxMode);

    return {
      'id': host.id,
      'label': host.label,
      'maxMode': maxMode.name,
      'protocol': host.protocol,
      'groups': groupNames,
      'jumpHost': jumpLabel,
      'access': mode == null ? 'none' : 'granted',
      'mode': mode?.name,
    };
  }
}

/// `request_host_access` — the one and only door to a host grant.
///
/// `open_session` deliberately never opens an approval window itself (see
/// `session_tools.dart`); this is the single place a human is asked, and the
/// plan requires the agent to front-load everything it needs into one
/// batched, partially-approvable request rather than trickling in one host
/// at a time.
class RequestHostAccessTool with McpArgReaders implements McpToolHandler {
  final HostsRepository hostsRepository;
  final HostsDao hostsDao;
  final McpGrantRepository grantRepository;
  final ApprovalCoordinator approvalCoordinator;
  final McpAuditRepository auditRepository;

  const RequestHostAccessTool({
    required this.hostsRepository,
    required this.hostsDao,
    required this.grantRepository,
    required this.approvalCoordinator,
    required this.auditRepository,
  });

  @override
  String get name => 'request_host_access';

  @override
  McpToolDefinition get definition => McpToolDefinition(
    name: name,
    description:
        'Requests access to one or more hosts in a single approval window. '
        'The user can approve some hosts and deny others, and can change the '
        'mode per host, so the response reports "granted" and "denied" '
        'separately — plan around what you did not get rather than assuming '
        'the whole batch succeeded. A grant below the mode you asked for '
        'carries "requestedMode" and a "reason": "max_mode" (the host allows '
        'no more), "user_lowered", or, when you asked to raise a grant you '
        'already hold, "user_denied", "timeout" or "cancelled" with the held '
        'grant kept. Do not re-ask an upgrade the user denied; work within '
        'the mode you have or tell the user. Call this once with everything you '
        'expect to need for the task at hand: open_session refuses to open '
        'an approval window on its own, so a host missing from this call '
        'means a HOST_ACCESS_REQUIRED error later.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'hostIds': {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': 1,
          'description':
              'The opaque hostId values (from list_hosts or describe_host) '
              'to request access to.',
        },
        'reason': {
          'type': 'string',
          'description':
              'A short, human-readable reason for the request. Shown to the '
              'user verbatim in the approval window, e.g. "Investigating '
              'disk usage on the web tier".',
        },
        'requestedMode': {
          'type': 'string',
          'enum': ['readonly', 'guarded', 'autonomous'],
          'description':
              'Access mode to request for every host in this call. Never '
              'granted above a host\'s own maxMode (see list_hosts), and the '
              'user can still lower it per host in the approval window. '
              'Omit to ask for each host\'s maxMode.',
        },
      },
      'required': ['hostIds', 'reason'],
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> execute(McpToolContext ctx, Map<String, Object?> args) async {
    final hostIds = requireStringList(args, 'hostIds');
    final reason = requireString(args, 'reason');
    final requestedMode = _parseRequestedMode(
      optionalString(args, 'requestedMode'),
    );

    final granted = <HostAccessGrant>[];
    final denied = <HostAccessDenial>[];
    final candidates = <HostAccessCandidate>[];
    final labels = <String, String>{};
    // Hosts already held at a lower mode, asked for more: the held grant is
    // what stands if the upgrade is not approved.
    final upgrades = <String, HostAccessGrant>{};
    // Upgrades the window did not approve: kept at the held mode, but audited
    // as the denial they were.
    final refusedUpgrades = <String>{};

    final live = {
      for (final g in await grantRepository.activeGrantsForClient(
        ctx.clientId,
        connectionScopeId: ctx.connectionScopeId,
      ))
        g.hostId: g,
    };

    for (final hostId in hostIds) {
      final host = await hostsRepository.getHostById(hostId);
      if (host == null || host.workspaceId != ctx.workspaceId) {
        // Cross-workspace or nonexistent hosts are reported exactly like a
        // hidden host — the agent must not be able to tell "does not exist"
        // apart from "not visible to you" by probing ids.
        denied.add(HostAccessDenial(hostId: hostId, reason: 'not_visible'));
        continue;
      }

      final row = await _hostRow(hostsDao, hostId);
      if (!_isMcpVisible(row)) {
        denied.add(HostAccessDenial(hostId: hostId, reason: 'not_visible'));
        continue;
      }
      labels[hostId] = host.label;
      final maxMode = _maxModeOf(row);

      final held = live[hostId];
      if (held != null) {
        final heldGrant = HostAccessGrant(
          hostId: hostId,
          mode: McpAccessMode.fromName(held.mode).atMost(maxMode),
          expiresAt: held.expiresAt,
          sessionScoped: held.connectionScopeId != null,
        );
        // Only an explicit ask for more than is held, within the host's max
        // access, opens the window again. An omitted mode is a repeat,
        // answered from the grant without a prompt, and an ask for less never
        // lowers it.
        final wanted = requestedMode?.atMost(maxMode);
        if (wanted == null || wanted.index <= heldGrant.mode.index) {
          granted.add(
            requestedMode != null && requestedMode.index > heldGrant.mode.index
                ? _lowered(heldGrant, requestedMode, 'max_mode')
                : heldGrant,
          );
          continue;
        }
        upgrades[hostId] = heldGrant;
      } else if (await grantRepository.isInCooldown(ctx.clientId, hostId)) {
        // Cooldown auto-denies WITHOUT opening a window — the whole point of
        // the cooldown is to stop a looping agent from re-prompting the user
        // for something it was just told no to.
        denied.add(HostAccessDenial(hostId: hostId, reason: 'cooldown'));
        continue;
      }

      candidates.add(
        HostAccessCandidate(
          hostId: hostId,
          label: host.label,
          suggestedMode: (requestedMode ?? maxMode).atMost(maxMode),
          maxMode: maxMode,
        ),
      );
    }

    if (candidates.isNotEmpty) {
      final result = await approvalCoordinator.requestHostAccess(
        HostAccessRequest(
          clientId: ctx.clientId,
          clientName: ctx.clientName,
          workspaceId: ctx.workspaceId,
          reason: reason,
          candidates: candidates,
        ),
      );

      final maxModes = {for (final c in candidates) c.hostId: c.maxMode};
      for (final answer in result.granted) {
        final maxMode = maxModes[answer.hostId] ?? McpAccessMode.readonly;
        final asked = requestedMode ?? maxMode;
        // Capped again here, not only in the window: what is stored must hold
        // whatever the UI let through.
        var grant = HostAccessGrant(
          hostId: answer.hostId,
          mode: answer.mode.atMost(maxMode),
          expiresAt: answer.expiresAt,
          sessionScoped: answer.sessionScoped,
        );
        if (grant.mode.index < asked.index) {
          grant = _lowered(
            grant,
            asked,
            grant.mode == maxMode ? 'max_mode' : 'user_lowered',
          );
        }
        await grantRepository.grant(
          clientId: ctx.clientId,
          hostId: grant.hostId,
          mode: grant.mode,
          expiresAt: grant.expiresAt,
          connectionScopeId: grant.sessionScoped ? ctx.connectionScopeId : null,
        );
        granted.add(grant);
      }
      for (final denial in result.denied) {
        final held = upgrades[denial.hostId];
        if (held != null) {
          // A refused upgrade leaves the held grant as it was. No cooldown:
          // on an existing row it would suspend the held grant too.
          // ponytail: so an agent can re-ask an upgrade at once; the reason
          // in the answer tells it not to. Add an upgrade-only cooldown if
          // agents loop on it.
          granted.add(_lowered(held, requestedMode!, denial.reason));
          refusedUpgrades.add(denial.hostId);
          continue;
        }
        // Only the user saying no cools down. A prompt that timed out unseen
        // in the queue, or was cancelled by a lock, is not an answer.
        if (denial.reason == 'user_denied') {
          await grantRepository.denyWithCooldown(
            clientId: ctx.clientId,
            hostId: denial.hostId,
          );
        }
        denied.add(denial);
      }
    }

    // One row per host, so the log shows what was asked for and how each
    // host was answered. Only candidates went through the window; the rest
    // were answered without a human (an existing grant, cooldown, hidden).
    final prompted = {for (final c in candidates) c.hostId};
    final redactedReason = const OutputRedactor().redact(reason).text;
    for (final grant in granted) {
      final refused = refusedUpgrades.contains(grant.hostId);
      await _audit(
        ctx,
        grant.hostId,
        labels[grant.hostId],
        refused
            ? AuditDecision.denied
            : prompted.contains(grant.hostId)
            ? AuditDecision.confirmed
            : AuditDecision.allowed,
        {
          'reason': redactedReason,
          'mode': grant.mode.name,
          if (grant.requestedMode != null)
            'requestedMode': grant.requestedMode!.name,
          if (refused) 'denial': grant.reason,
        },
      );
    }
    for (final denial in denied) {
      await _audit(
        ctx,
        denial.hostId,
        labels[denial.hostId],
        prompted.contains(denial.hostId)
            ? AuditDecision.denied
            : AuditDecision.autoDenied,
        {'reason': redactedReason, 'denial': denial.reason},
      );
    }

    return HostAccessResult(granted: granted, denied: denied).toJson();
  }

  Future<void> _audit(
    McpToolContext ctx,
    String hostId,
    String? hostLabel,
    AuditDecision decision,
    Map<String, Object?> args,
  ) => auditRepository.record(
    clientId: ctx.clientId,
    clientName: ctx.clientName,
    workspaceId: ctx.workspaceId,
    hostId: hostId,
    hostLabel: hostLabel,
    tool: name,
    args: args,
    decision: decision,
  );

  /// [grant] marked as below what was [asked], and [why].
  static HostAccessGrant _lowered(
    HostAccessGrant grant,
    McpAccessMode asked,
    String why,
  ) => HostAccessGrant(
    hostId: grant.hostId,
    mode: grant.mode,
    expiresAt: grant.expiresAt,
    sessionScoped: grant.sessionScoped,
    requestedMode: asked,
    reason: why,
  );

  /// An unknown name is reported rather than read as `readonly` (what
  /// [McpAccessMode.fromName] falls back to), which would hide the agent's
  /// mistake instead of telling it.
  McpAccessMode? _parseRequestedMode(String? raw) {
    if (raw == null) return null;
    if (!McpAccessMode.values.any((m) => m.name == raw)) {
      throw McpToolException(
        McpErrorCode.internal,
        'Argument "requestedMode" must be "readonly", "guarded" or '
        '"autonomous", got "$raw".',
      );
    }
    return McpAccessMode.fromName(raw);
  }
}
