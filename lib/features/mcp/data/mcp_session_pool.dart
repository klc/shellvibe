import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../core/mcp/shell/persistent_shell_session.dart';
import '../../../core/mcp/shell/shell_channel.dart';
import '../../hosts/domain/models/host_model.dart';
import '../domain/models/mcp_enums.dart';
import '../domain/models/mcp_models.dart';
import '../domain/services/mcp_session_mirror.dart';
import 'mcp_host_connector.dart';

/// One open agent shell on one host: the SSH connection underneath, the
/// normalized persistent shell riding it, and the bookkeeping the pool needs
/// to enforce limits and time out idle sessions.
class McpSession {
  final String sessionId;
  final String hostId;
  final String clientId;
  final String hostLabel;

  /// Id of the read-only terminal tab this session surfaces as, once one has
  /// been registered. Null until the tab exists.
  String? tabId;

  final McpConnection connection;
  final PersistentShellSession shell;
  final DateTime openedAt;

  /// Bumped by callers on every tool call that touches this session (a
  /// `run_command`, an `interrupt`, ...). The pool only reads it — updating
  /// it is the tool handler's job, since the pool itself never runs a
  /// command.
  DateTime lastActivityAt;

  McpSession({
    required this.sessionId,
    required this.hostId,
    required this.clientId,
    required this.hostLabel,
    this.tabId,
    required this.connection,
    required this.shell,
    required this.openedAt,
    required this.lastActivityAt,
  });

  bool get busy => shell.isBusy;
}

/// Owns every open MCP shell session across every connected client.
///
/// `SSHSessionManager` is single-client: [SSHSessionManager.connect] calls
/// `close()` on entry, so one manager instance can only ever carry one live
/// connection at a time (see `core/network/ssh_session_manager.dart:103`).
/// Multiplexing several MCP sessions over one already-connected manager is
/// therefore not an option — reusing a manager for a second [open] would
/// silently kill whatever session was already using it. Every [open] call
/// dials a brand new manager (via [McpHostConnector.connect]), so sessions on
/// the same host are always independent TCP connections.
class McpSessionPool {
  final McpHostConnector connector;
  final int maxSessionsPerClient;

  /// The "Limits" knobs from Settings. Mutable because they are user
  /// settings on a pool that lives as long as the app: `McpSettingsNotifier`
  /// writes them here on load and on every change, and each is read at the
  /// moment it applies (sweep tick, shell creation, `run_command` call).
  /// The pool is the one object the shell layer and `run_command` both hold,
  /// which is why they live here and not on a settings service.
  Duration idleTimeout;
  int outputCapBytes;
  Duration defaultCommandTimeout;

  /// Where each session shows itself to the user. Defaults to a mirror with
  /// no surface so the pool works unchanged in tests and anywhere the UI is
  /// not up yet; the app replaces it with the terminal-tab one.
  final McpSessionMirror mirror;

  final Map<String, McpSession> _sessions = {};
  final Map<String, StreamSubscription<Object?>> _clientChangeSubs = {};
  Timer? _idleSweepTimer;
  bool _disposed = false;

  McpSessionPool({
    required this.connector,
    this.mirror = const NullMcpSessionMirror(),
    this.maxSessionsPerClient = 10,
    this.idleTimeout = const Duration(minutes: 30),
    this.outputCapBytes = 100 * 1024,
    this.defaultCommandTimeout = const Duration(seconds: 60),
  }) {
    // A period well under the default idle timeout so a session is reaped
    // within a minute of going stale rather than lingering until the next
    // long-interval tick.
    _idleSweepTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _sweepIdle(),
    );
  }

  /// Opens a new PTY-less shell session on [host] for [clientId].
  ///
  /// Throws [McpToolException] with [McpErrorCode.sessionLimitReached] once
  /// [clientId] already holds [maxSessionsPerClient] sessions — a cap meant
  /// to stop a looping agent from drowning a host in connections, not a
  /// per-host limit.
  Future<McpSession> open({
    required String clientId,
    required String clientName,
    required String mode,
    required HostModel host,
  }) async {
    if (sessionsForClient(clientId).length >= maxSessionsPerClient) {
      throw McpToolException(
        McpErrorCode.sessionLimitReached,
        'Client "$clientId" already holds the maximum of '
        '$maxSessionsPerClient concurrent MCP sessions.',
      );
    }

    final connection = await connector.connect(host);

    // Opens a fresh PTY-less shell over the same still-authenticated SSH
    // client. Used both for the initial channel and as [PersistentShellSession]'s
    // `reopen` callback, so a stuck/desynced channel can be replaced without
    // re-running the SSH handshake.
    Future<ShellChannel> openPtylessShell() async {
      final session = await connection.target.openShell(requestPty: false);
      return SshShellChannel(session);
    }

    PersistentShellSession? shell;
    try {
      final channel = await openPtylessShell();
      shell = PersistentShellSession(
        channel: channel,
        reopen: openPtylessShell,
        outputCapBytes: outputCapBytes,
      );
      await shell.initialize();
    } catch (_) {
      await shell?.close();
      await connection.close();
      rethrow;
    }

    final sessionId = const Uuid().v4();
    final now = DateTime.now();
    final session = McpSession(
      sessionId: sessionId,
      hostId: host.id,
      clientId: clientId,
      hostLabel: host.label,
      connection: connection,
      shell: shell,
      openedAt: now,
      lastActivityAt: now,
    );

    _sessions[sessionId] = session;
    // Only the target manager is watched: a dropped jump hop shows up here
    // too, because losing it takes the tunneled target client down with it
    // (the target manager's own keep-alive ping starts failing and its
    // `clientChanges` emits null), so one subscription covers both cases.
    _clientChangeSubs[sessionId] = connection.target.clientChanges.listen((
      client,
    ) {
      if (client == null) unawaited(_dropSession(sessionId));
    });

    // The watchable tab comes up before the session id is ever handed to the
    // agent, so there is no window in which an agent could run a command
    // nobody could have seen. A mirror that cannot open one returns null and
    // the session simply runs unwatched — visibility must not be able to
    // fail the session it is reporting on.
    try {
      session.tabId = await mirror.open(
        sessionId: sessionId,
        hostLabel: host.label,
        cwd: shell.cwd,
        clientName: clientName,
        mode: mode,
        onUserClosed: () => close(sessionId),
      );
    } catch (_) {}

    return session;
  }

  McpSession? find(String sessionId) => _sessions[sessionId];

  /// [find], refusing an id that belongs to a different client: a client must
  /// never be able to touch, list, or even learn of another client's session
  /// by guessing its id, so "not yours" and "does not exist" read the same.
  McpSession requireOwned(String clientId, String sessionId) {
    final session = find(sessionId);
    if (session == null || session.clientId != clientId) {
      throw McpToolException(
        McpErrorCode.sessionNotFound,
        'No open session with id "$sessionId" for this client.',
      );
    }
    return session;
  }

  List<McpSession> sessionsForClient(String clientId) =>
      _sessions.values.where((s) => s.clientId == clientId).toList();

  /// Closes one session: the shell, then the SSH connection underneath.
  /// A no-op for an id that is not open (already closed, or never existed).
  Future<void> close(String sessionId, {String? reason}) async {
    final session = _sessions.remove(sessionId);
    if (session == null) return;
    await _clientChangeSubs.remove(sessionId)?.cancel();
    await _closeSurface(session, reason ?? 'session closed');
    await session.shell.close();
    await session.connection.close();
  }

  Future<void> closeForClient(String clientId) async {
    for (final id in sessionsForClient(
      clientId,
    ).map((s) => s.sessionId).toList()) {
      await close(id);
    }
  }

  /// Closes every open session, for every client. Called by both the vault
  /// lock path and the panic button — neither can afford to leave a session
  /// behind, so this never partially applies: a failure to close one session
  /// does not stop the rest from being attempted.
  Future<void> closeAll() async {
    for (final id in _sessions.keys.toList()) {
      try {
        await close(id);
      } catch (_) {
        // Best-effort: a session that fails to close cleanly (e.g. the
        // socket is already gone) must not block the remaining sessions
        // from being torn down too.
      }
    }
  }

  /// Stops the idle sweep and drops bookkeeping for whatever sessions remain.
  /// Connections are closed fire-and-forget since `dispose` is synchronous —
  /// this is meant for provider teardown, where the process is going away
  /// with them regardless.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _idleSweepTimer?.cancel();
    _idleSweepTimer = null;
    for (final sub in _clientChangeSubs.values) {
      unawaited(sub.cancel());
    }
    _clientChangeSubs.clear();
    for (final session in _sessions.values) {
      unawaited(_closeSurface(session, 'ShellVibe is shutting down'));
      unawaited(session.shell.close());
      unawaited(session.connection.close());
    }
    _sessions.clear();
  }

  /// Reacts to a manager's `clientChanges` emitting null: the connection
  /// dropped out from under the session, so it is dead and removed. The
  /// connection is closed anyway (idempotent — the manager already tore down
  /// its own client/socket) so timers and controllers on it are released.
  Future<void> _dropSession(String sessionId) =>
      close(sessionId, reason: 'connection lost');

  /// Closes a session's watchable surface, swallowing anything it throws:
  /// this runs on every teardown path, including the vault-lock and panic
  /// ones, where failing to close the *session* because its tab misbehaved
  /// would be exactly the wrong trade.
  Future<void> _closeSurface(McpSession session, String reason) async {
    final surfaceId = session.tabId;
    if (surfaceId == null) return;
    session.tabId = null;
    try {
      await mirror.close(surfaceId, reason: reason);
    } catch (_) {}
  }

  void _sweepIdle() {
    final now = DateTime.now();
    final expired = _sessions.values
        .where((s) => !s.busy && now.difference(s.lastActivityAt) > idleTimeout)
        .map((s) => s.sessionId)
        .toList();
    for (final id in expired) {
      unawaited(close(id, reason: 'idle timeout'));
    }
  }
}
