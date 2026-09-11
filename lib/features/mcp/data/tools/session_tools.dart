import '../../../../core/mcp/mcp_protocol.dart';
import '../../../hosts/data/repositories/hosts_repository.dart';
import '../../domain/models/mcp_enums.dart';
import '../../domain/models/mcp_models.dart';
import '../mcp_session_pool.dart';
import '../repositories/mcp_grant_repository.dart';
import 'mcp_tool_handler.dart';

/// Shared session lookup: every session tool but `open_session` needs "find
/// this id, and refuse it if it belongs to a different client" — a client
/// must never be able to touch, list, or even learn of another client's
/// session by guessing its id.
McpSession _requireOwnedSession(
  McpSessionPool pool,
  McpToolContext ctx,
  String sessionId,
) {
  final session = pool.find(sessionId);
  if (session == null || session.clientId != ctx.clientId) {
    throw McpToolException(
      McpErrorCode.sessionNotFound,
      'No open session with id "$sessionId" for this client.',
    );
  }
  return session;
}

/// `open_session` — turns a host grant into a live, normalized shell.
///
/// Deliberately does NOT prompt for access itself: `docs/mcp_plan.md`'s
/// access model requires the agent to front-load every host it needs via
/// `request_host_access` in one batched, partially-approvable window. If
/// this tool opened its own approval window on a missing grant, that
/// contract would be bypassable one host at a time, defeating the point of
/// batching. A missing grant is therefore always `HOST_ACCESS_REQUIRED`,
/// never a fresh prompt.
class OpenSessionTool with McpArgReaders implements McpToolHandler {
  final McpSessionPool sessionPool;
  final HostsRepository hostsRepository;
  final McpGrantRepository grantRepository;

  const OpenSessionTool({
    required this.sessionPool,
    required this.hostsRepository,
    required this.grantRepository,
  });

  @override
  String get name => 'open_session';

  @override
  McpToolDefinition get definition => McpToolDefinition(
    name: name,
    description:
        'Opens a new persistent, PTY-less shell session on a host you '
        'already have access to (see request_host_access). Fails with '
        'HOST_ACCESS_REQUIRED if you do not — this tool never prompts the '
        'user itself, request access first. The returned session stays open '
        '(and visible to the user in a read-only terminal tab) until '
        'close_session, an idle timeout, or the MCP connection drops; use '
        'the returned sessionId with run_command.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'hostId': {
          'type': 'string',
          'description':
              'The opaque id of the host to connect to, as returned by '
              'list_hosts or request_host_access.',
        },
      },
      'required': ['hostId'],
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> execute(McpToolContext ctx, Map<String, Object?> args) async {
    final hostId = requireString(args, 'hostId');

    final mode = await grantRepository.effectiveMode(ctx.clientId, hostId);
    if (mode == null) {
      throw McpToolException(
        McpErrorCode.hostAccessRequired,
        'No access grant for host "$hostId". Call request_host_access for '
        'this host before opening a session.',
      );
    }

    final host = await hostsRepository.getHostById(hostId);
    if (host == null || host.workspaceId != ctx.workspaceId) {
      throw McpToolException(
        McpErrorCode.hostNotVisible,
        'No host with id "$hostId" is visible to this client.',
      );
    }

    final session = await sessionPool.open(
      clientId: ctx.clientId,
      clientName: ctx.clientName,
      mode: mode.name,
      host: host,
    );

    // `uname -a` / `echo $0` are run unquoted-literal on purpose (not passed
    // through the agent's own command path): they are fixed diagnostic
    // probes, not agent input, so there is nothing here for the policy
    // engine to evaluate — every open session gets exactly these two reads
    // regardless of host mode.
    final uname = await session.shell.run('uname -a');
    final shell = await session.shell.run(r'echo $0');
    session.lastActivityAt = DateTime.now();

    return {
      'sessionId': session.sessionId,
      'cwd': session.shell.cwd,
      'shell': shell.stdout.trim(),
      'uname': uname.stdout.trim(),
      'mode': mode.name,
      'tabId': session.tabId,
    };
  }
}

/// `list_sessions` — every session this client currently holds, across every
/// host.
class ListSessionsTool implements McpToolHandler {
  final McpSessionPool sessionPool;

  const ListSessionsTool({required this.sessionPool});

  @override
  String get name => 'list_sessions';

  @override
  McpToolDefinition get definition => McpToolDefinition(
    name: name,
    description:
        'Lists every session this client currently has open, across every '
        'host, including whether each one is busy running a command.',
    inputSchema: const {
      'type': 'object',
      'properties': <String, Object?>{},
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> execute(McpToolContext ctx, Map<String, Object?> args) async {
    final sessions = sessionPool.sessionsForClient(ctx.clientId);
    return sessions
        .map(
          (session) => {
            'sessionId': session.sessionId,
            'hostId': session.hostId,
            'hostLabel': session.hostLabel,
            'cwd': session.shell.cwd,
            'openedAt': session.openedAt.toIso8601String(),
            'busy': session.busy,
          },
        )
        .toList();
  }
}

/// `close_session` — ends one session immediately, freeing its slot against
/// the per-client session cap.
class CloseSessionTool with McpArgReaders implements McpToolHandler {
  final McpSessionPool sessionPool;

  const CloseSessionTool({required this.sessionPool});

  @override
  String get name => 'close_session';

  @override
  McpToolDefinition get definition => McpToolDefinition(
    name: name,
    description:
        'Closes an open session: tears down its shell and SSH connection. '
        'The session id becomes invalid immediately; open a new session to '
        'reach the same host again.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'sessionId': {
          'type': 'string',
          'description': 'The sessionId returned by open_session.',
        },
      },
      'required': ['sessionId'],
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> execute(McpToolContext ctx, Map<String, Object?> args) async {
    final sessionId = requireString(args, 'sessionId');
    _requireOwnedSession(sessionPool, ctx, sessionId);
    await sessionPool.close(sessionId);
    return {'ok': true};
  }
}

/// `interrupt` — sends Ctrl-C to a session without waiting for a stuck
/// `run_command` call to time out on its own.
class InterruptTool with McpArgReaders implements McpToolHandler {
  final McpSessionPool sessionPool;

  const InterruptTool({required this.sessionPool});

  @override
  String get name => 'interrupt';

  @override
  McpToolDefinition get definition => McpToolDefinition(
    name: name,
    description:
        'Stops whatever is running on a session, e.g. a command taking far '
        'longer than expected. Safe to call even if nothing is currently '
        'running. This resets the session\'s shell: the working directory is '
        'restored, but shell variables and background jobs are gone, and any '
        'run_command still in flight returns immediately marked interrupted. '
        'Plan on having lost that state rather than assuming continuity.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'sessionId': {
          'type': 'string',
          'description': 'The sessionId returned by open_session.',
        },
      },
      'required': ['sessionId'],
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> execute(McpToolContext ctx, Map<String, Object?> args) async {
    final sessionId = requireString(args, 'sessionId');
    final session = _requireOwnedSession(sessionPool, ctx, sessionId);
    await session.shell.interrupt();
    session.lastActivityAt = DateTime.now();
    final surfaceId = session.tabId;
    if (surfaceId != null) {
      sessionPool.mirror.writeNotice(
        surfaceId,
        'agent interrupted the session — shell rebuilt',
      );
    }
    // `sessionReset` is reported for the same reason `run_command` reports
    // it: interrupting here is implemented by rebuilding the shell, so the
    // agent must know the environment it built up no longer exists.
    return {'ok': true, 'sessionReset': true, 'cwd': session.shell.cwd};
  }
}
