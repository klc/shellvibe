import '../../../../core/mcp/mcp_protocol.dart';
import '../../../../shared/database/app_database.dart' show Host;
import '../../../../shared/database/daos/hosts_dao.dart';
import '../../../../shared/database/daos/workspaces_dao.dart';
import '../../../hosts/data/repositories/hosts_repository.dart';
import '../../domain/models/mcp_enums.dart';
import '../../domain/models/mcp_models.dart';
import '../../domain/services/approval_coordinator.dart';
import '../repositories/mcp_grant_repository.dart';
import 'mcp_tool_handler.dart';

/// Reads the three MCP-specific `Hosts` columns (`environment`, `mcpVisible`,
/// `mcpDefaultMode`) directly off [HostsDao].
///
/// [HostsRepository]'s `HostModel` does not carry these fields — it predates
/// the `schemaVersion` 7 → 8 migration that added them (see
/// `docs/mcp_plan.md` Faz 3) and is out of scope for this change (it is not
/// one of this file's owned files). Every discovery tool below still goes
/// through [HostsRepository] first for the fields it already has (label,
/// hostname, port, group, jump host); this helper only fills the gap, by id,
/// straight from the DAO both `HostsRepository` and `HostsDao` share.
Future<Host?> _hostRow(HostsDao hostsDao, String hostId) =>
    hostsDao.getHostById(hostId);

HostEnvironment _environmentOf(Host? row) => row == null
    ? HostEnvironment.dev
    : HostEnvironment.fromName(row.environment);

bool _isMcpVisible(Host? row) => row == null || row.mcpVisible;

McpAccessMode _defaultModeOf(Host? row) => row == null
    ? McpAccessMode.readonly
    : McpAccessMode.fromName(row.mcpDefaultMode);

/// `list_hosts` — the agent's entire inventory of what it *could* ask to
/// reach.
///
/// The docstring below is load-bearing, not decorative: an agent reads it to
/// learn it can never obtain a hostname/port/credential to connect with
/// directly, only an opaque [Host.id] to hand to other tools. `tags[]` from
/// the plan's original draft is intentionally absent — `Hosts` has no tags
/// column, so `group` (resolved from `groupId`) is exposed instead.
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
        'Lists every host registered in this client\'s workspace that is '
        'visible to MCP agents (a host owner can hide any host from agents '
        'entirely; hidden hosts never appear here). Returns '
        '{"workspace": {"id", "name"}, "hosts": [...]}. IMPORTANT: this '
        'token is bound to ONE workspace for its whole life, named in '
        '"workspace" — switching workspaces in the ShellVibe window does not '
        'change what this tool returns, and hosts saved in another workspace '
        'are never listed here. If the user asks for a host that is missing, '
        'tell them which workspace you can see and that the host may live in '
        'a different one, which needs its own token from Settings -> AI '
        'Access. For each host this reports whether the caller currently has '
        'access ("granted"/"none") and, if granted, the access mode. The '
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

      final mode = await grantRepository.effectiveMode(ctx.clientId, host.id);
      final groupName = await _groupNameOf(host.groupId);

      result.add({
        'id': host.id,
        'label': host.label,
        'hostname': host.hostname,
        'port': host.port,
        'environment': _environmentOf(row).name,
        'group': groupName,
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

  Future<String?> _groupNameOf(String? groupId) async {
    if (groupId == null) return null;
    final group = await hostsRepository.getHostGroupById(groupId);
    return group?.name;
  }
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

    final groupName = host.groupId == null
        ? null
        : (await hostsRepository.getHostGroupById(host.groupId!))?.name;
    final jumpLabel = host.jumpHostId == null
        ? null
        : (await hostsRepository.getHostById(host.jumpHostId!))?.label;
    final mode = await grantRepository.effectiveMode(ctx.clientId, hostId);

    return {
      'id': host.id,
      'label': host.label,
      'hostname': host.hostname,
      'port': host.port,
      'environment': _environmentOf(row).name,
      'protocol': host.protocol,
      'group': groupName,
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

  const RequestHostAccessTool({
    required this.hostsRepository,
    required this.hostsDao,
    required this.grantRepository,
    required this.approvalCoordinator,
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
        'the whole batch succeeded. Call this once with everything you '
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
          'enum': ['readonly', 'guarded'],
          'description':
              'Access mode to request for every host in this call, instead '
              'of each host\'s own configured default. The user can still '
              'override it per host in the approval window. Omit to use '
              'each host\'s default mode. ("autonomous" is not offered in '
              'this version.)',
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

      if (await _inCooldown(ctx.clientId, hostId)) {
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
          environment: _environmentOf(row),
          suggestedMode: requestedMode ?? _defaultModeOf(row),
        ),
      );
    }

    if (candidates.isNotEmpty) {
      final result = await approvalCoordinator.requestHostAccess(
        HostAccessRequest(
          clientId: ctx.clientId,
          clientName: ctx.clientName,
          reason: reason,
          candidates: candidates,
        ),
      );

      for (final grant in result.granted) {
        await grantRepository.grant(
          clientId: ctx.clientId,
          hostId: grant.hostId,
          mode: grant.mode,
          expiresAt: grant.expiresAt,
        );
        granted.add(grant);
      }
      for (final denial in result.denied) {
        await grantRepository.denyWithCooldown(
          clientId: ctx.clientId,
          hostId: denial.hostId,
        );
        denied.add(denial);
      }
    }

    return HostAccessResult(granted: granted, denied: denied).toJson();
  }

  /// `McpAccessMode.fromName` maps any unrecognized string to `readonly` as
  /// a fail-safe default, but `"autonomous"` IS a recognized name — so that
  /// fallback would never fire for it. v0 does not offer `autonomous` (see
  /// `docs/mcp_plan.md`, "v0 kapsamı"), so it is rejected explicitly here
  /// instead of being silently downgraded, which would hide the agent's
  /// mistake instead of reporting it.
  McpAccessMode? _parseRequestedMode(String? raw) {
    if (raw == null) return null;
    if (raw != 'readonly' && raw != 'guarded') {
      throw McpToolException(
        McpErrorCode.internal,
        'Argument "requestedMode" must be "readonly" or "guarded" '
        '("autonomous" is not offered in this version), got "$raw".',
      );
    }
    return McpAccessMode.fromName(raw);
  }

  Future<bool> _inCooldown(String clientId, String hostId) async {
    final grant = await grantRepository.dao.findGrant(clientId, hostId);
    final until = grant?.cooldownUntil;
    if (until == null) return false;
    return until.isAfter(DateTime.now().toUtc());
  }
}
