import '../../../../core/mcp/mcp_protocol.dart';
import '../../../../shared/database/daos/identities_dao.dart';
import '../../../hosts/data/repositories/hosts_repository.dart';
import '../../domain/models/mcp_enums.dart';
import '../../domain/models/mcp_models.dart';
import '../../domain/services/approval_coordinator.dart';
import '../repositories/mcp_audit_repository.dart';
import 'mcp_tool_handler.dart';

/// `add_host` — save a new server, after the user has said yes.
///
/// The agent proposes only an address: a label, hostname, port and user
/// name. Credentials never come from it; the user attaches one of their
/// identities in the approval window, or none. The new host is visible to
/// agents at the default max access, and not granted: access still goes
/// through `request_host_access`, the one door to a grant.
class AddHostTool with McpArgReaders implements McpToolHandler {
  final HostsRepository hostsRepository;
  final IdentitiesDao identitiesDao;
  final McpAuditRepository auditRepository;
  final ApprovalCoordinator approvalCoordinator;

  /// Called after a host is saved, so the app's host list shows it.
  final void Function() onHostAdded;

  const AddHostTool({
    required this.hostsRepository,
    required this.identitiesDao,
    required this.auditRepository,
    required this.approvalCoordinator,
    required this.onHostAdded,
  });

  @override
  String get name => 'add_host';

  @override
  McpToolDefinition get definition => McpToolDefinition(
    name: name,
    description:
        'Saves a new SSH server in ShellVibe, after the user approves it in '
        'a window that shows the address you give. You give only the '
        'address: never a password, key or other credential. The user '
        'attaches their own credentials in that window. If a host with the '
        'same hostname and port is already saved, nothing is added and you '
        'get its hostId (status "exists"); a label another host already has '
        'is refused. A saved host is not granted to you: call '
        'request_host_access for it before open_session. Its host key is not '
        'trusted yet, so the first open_session may answer '
        'HOST_KEY_UNTRUSTED until the user connects once from ShellVibe. Use '
        'this only when the user asked you to work on a server that '
        'list_hosts does not have.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'label': {
          'type': 'string',
          'description': 'A short name the user will recognize, e.g. "web-1".',
        },
        'hostname': {
          'type': 'string',
          'description': 'The DNS name or IP address to connect to.',
        },
        'port': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 65535,
          'description': 'The SSH port. Defaults to 22.',
        },
        'username': {
          'type': 'string',
          'description':
              'The user to log in as, if known. It is used over the user '
              'name of the identity the user attaches.',
        },
      },
      'required': ['label', 'hostname'],
      'additionalProperties': false,
    },
  );

  // Not starting with "-": the hostname and user name end up on an ssh
  // command line, where a leading dash would be an option.
  static final _hostnamePattern = RegExp(
    r'^[A-Za-z0-9_\[:][A-Za-z0-9._:%\[\]-]*$',
  );
  static final _usernamePattern = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9._@-]*$');
  static final _controlChars = RegExp(r'[\x00-\x1f\x7f]');

  /// Refusals already written to the log with their own, richer entry.
  static final _audited = Expando<bool>();

  @override
  Future<Object?> execute(McpToolContext ctx, Map<String, Object?> args) async {
    try {
      return await _add(ctx, args);
    } on McpToolException catch (e) {
      if (_audited[e] ?? false) rethrow;
      // A malformed request is logged too: a hostname such as
      // "-oProxyCommand=..." is the attempt most worth seeing.
      await auditRepository.record(
        clientId: ctx.clientId,
        clientName: ctx.clientName,
        workspaceId: ctx.workspaceId,
        tool: name,
        args: {
          for (final key in ['label', 'hostname', 'port', 'username'])
            if (args[key] != null) key: '${args[key]}',
          'rejected': e.message,
        },
        decision: AuditDecision.denied,
      );
      rethrow;
    }
  }

  Future<Object?> _add(McpToolContext ctx, Map<String, Object?> args) async {
    final label = requireString(args, 'label').trim();
    final hostname = requireString(args, 'hostname').trim();
    final port = optionalInt(args, 'port') ?? 22;
    final username = optionalString(args, 'username')?.trim();

    if (label.isEmpty || label.length > 100 || _controlChars.hasMatch(label)) {
      throw _invalid('"label" must be 1 to 100 characters, on one line.');
    }
    if (hostname.length > 253 || !_hostnamePattern.hasMatch(hostname)) {
      throw _invalid(
        '"hostname" must be a DNS name or an IP address, got "$hostname".',
      );
    }
    if (port < 1 || port > 65535) {
      throw _invalid('"port" must be between 1 and 65535, got $port.');
    }
    if (username != null &&
        username.isNotEmpty &&
        (username.length > 64 || !_usernamePattern.hasMatch(username))) {
      throw _invalid('"username" is not a valid user name: "$username".');
    }
    final user = username == null || username.isEmpty ? null : username;
    final address = {
      'label': label,
      'hostname': hostname,
      'port': port,
      'username': ?user,
    };

    final before = await _lookup(ctx, hostname, port, label);
    if (before != null) return before;

    final identities = await identitiesDao.getIdentitiesByWorkspace(
      ctx.workspaceId,
    );
    final decision = await approvalCoordinator.requestHostAdd(
      HostAddRequest(
        clientId: ctx.clientId,
        clientName: ctx.clientName,
        label: label,
        hostname: hostname,
        port: port,
        username: user,
        identities: [
          for (final i in identities)
            HostAddIdentity(id: i.id, title: i.title, username: i.username),
        ],
      ),
    );

    if (!decision.approved) {
      await _record(ctx, label, address, AuditDecision.denied);
      throw _logged(
        McpToolException(
          McpErrorCode.policyDenied,
          'The user declined to add "$label".',
        ),
      );
    }

    // The answer may have taken a minute: the same address or label may
    // have been saved meanwhile, by the user or another call.
    final after = await _lookup(ctx, hostname, port, label);
    if (after != null) return after;

    final identityId = identities.any((i) => i.id == decision.identityId)
        ? decision.identityId
        : null;
    final host = await hostsRepository.saveHost(
      workspaceId: ctx.workspaceId,
      label: label,
      hostname: hostname,
      port: port,
      username: user,
      // Only an identity of this workspace, whatever the window sent back.
      identityId: identityId,
    );
    onHostAdded();
    await _record(ctx, label, {
      ...address,
      'hostId': host.id,
    }, AuditDecision.confirmed);
    return {
      'status': 'added',
      'hostId': host.id,
      'label': host.label,
      'note':
          'Saved. It is not granted to you yet: call request_host_access for '
          'it before open_session. '
          '${identityId == null ? 'The user attached no credentials, so '
                    'connecting will fail until they add some in ShellVibe. ' : ''}'
          'If open_session answers HOST_KEY_UNTRUSTED, the user has to '
          'connect once from a ShellVibe terminal tab to accept the new '
          'server\'s host key: tell them, do not retry.',
    };
  }

  /// The answer for an address or label already in this workspace, or null
  /// to go on adding.
  ///
  /// The same address is reported with its id: the user chose that agents
  /// are told. The same label on another host an agent can see is refused:
  /// approval windows name hosts by label, so two alike would be confusable.
  Future<Map<String, Object?>?> _lookup(
    McpToolContext ctx,
    String hostname,
    int port,
    String label,
  ) async {
    final hosts = await hostsRepository.getHostsByWorkspace(ctx.workspaceId);
    final existing = hosts
        .where(
          (h) =>
              h.hostname.toLowerCase() == hostname.toLowerCase() &&
              h.port == port,
        )
        .firstOrNull;
    if (existing != null) {
      final args = {
        'hostname': hostname,
        'port': port,
        'existing': existing.id,
      };
      if (!existing.mcpVisible) {
        await _record(ctx, existing.label, args, AuditDecision.denied);
        throw _logged(
          McpToolException(
            McpErrorCode.hostNotVisible,
            'A host at $hostname:$port is already saved, but it is hidden '
            'from agents. Ask the user to make it visible to AI access.',
          ),
        );
      }
      await _record(ctx, existing.label, args, AuditDecision.allowed);
      return {
        'status': 'exists',
        'hostId': existing.id,
        'label': existing.label,
        'note':
            'Already saved; nothing was added. Call request_host_access for '
            'it if you have not been granted it.',
      };
    }
    final sameLabel = hosts.any(
      (h) => h.mcpVisible && h.label.toLowerCase() == label.toLowerCase(),
    );
    if (sameLabel) {
      throw _invalid(
        'Another host is already labelled "$label". Pick a label that tells '
        'them apart.',
      );
    }
    return null;
  }

  Future<void> _record(
    McpToolContext ctx,
    String hostLabel,
    Map<String, Object?> args,
    AuditDecision decision,
  ) => auditRepository.record(
    clientId: ctx.clientId,
    clientName: ctx.clientName,
    workspaceId: ctx.workspaceId,
    hostLabel: hostLabel,
    tool: name,
    args: args,
    decision: decision,
  );

  McpToolException _logged(McpToolException e) {
    _audited[e] = true;
    return e;
  }

  McpToolException _invalid(String message) =>
      McpToolException(McpErrorCode.internal, message);
}
