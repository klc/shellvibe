import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import '../../../../core/network/ssh_session_manager.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/domain/services/ssh_connect_planner.dart';
import '../../../vault/domain/models/identity_model.dart';

/// The SSH connections that port forwards ride on when no terminal is open.
///
/// A forward needs an authenticated SSH client and nothing else — no PTY, no
/// shell, no tab. Requiring the user to open a terminal session first (and to
/// keep it open) was an implementation detail leaking into the product: the
/// screen looked up "the active tab's client" and refused to start otherwise.
///
/// This pool opens that client itself, in the background, and keeps one per
/// host no matter how many rules use it. A rule started while a terminal tab
/// for the same host is already connected reuses the tab's client instead —
/// see `TunnelsNotifier.startRule` — so this only ever holds connections
/// nothing else was going to open.
///
/// Sessions are reference counted by rule id: the last [release] for a host
/// closes its connection, including every jump hop opened to reach it.
class TunnelSshPool {
  final SshConnectPlanner planner;

  /// Injected rather than constructed inline so tests can pool a fake, and so
  /// the pool does not have to know where the known-hosts store comes from.
  final SSHSessionManager Function() createSessionManager;

  /// Reads a stored identity for a jump hop. Jump hosts are resolved from the
  /// database mid-chain, so their credentials cannot be passed in up front the
  /// way the target host's are.
  final Future<IdentityModel?> Function(String identityId) readIdentity;

  TunnelSshPool({
    required this.planner,
    required this.createSessionManager,
    required this.readIdentity,
  });

  final Map<String, _PooledSession> _sessions = {};

  /// Connects in flight, keyed by host id, so two rules started at once on the
  /// same host share one dial instead of racing to open two.
  final Map<String, Future<SSHClient>> _pending = {};

  /// Host ids this pool currently holds a background connection for.
  Iterable<String> get connectedHostIds => _sessions.keys;

  /// True when [hostId]'s connection is this pool's, not a terminal tab's.
  bool holds(String hostId) => _sessions.containsKey(hostId);

  /// An authenticated client for [host], opening one if this pool does not
  /// already have a live one, and charging it to [ruleId].
  Future<SSHClient> acquire({
    required String ruleId,
    required HostModel host,
    IdentityModel? identity,
    HostKeyPromptCallback? onHostKeyPrompt,
  }) async {
    final existing = _sessions[host.id];
    if (existing != null) {
      final client = existing.manager.client;
      if (client != null && !client.isClosed) {
        existing.ruleIds.add(ruleId);
        return client;
      }
      // Dead but not yet cleaned up (the keep-alive may not have fired yet):
      // drop it and dial again rather than handing back a closed client.
      await _closeSession(host.id);
    }

    final inFlight = _pending[host.id];
    if (inFlight != null) {
      final client = await inFlight;
      _sessions[host.id]?.ruleIds.add(ruleId);
      return client;
    }

    final connect = _connect(
      host: host,
      identity: identity,
      onHostKeyPrompt: onHostKeyPrompt,
    );
    _pending[host.id] = connect;
    try {
      final client = await connect;
      _sessions[host.id]?.ruleIds.add(ruleId);
      return client;
    } finally {
      _pending.remove(host.id);
    }
  }

  Future<SSHClient> _connect({
    required HostModel host,
    IdentityModel? identity,
    HostKeyPromptCallback? onHostKeyPrompt,
  }) async {
    final jumpManagers = <SSHSessionManager>[];
    try {
      // ProxyJump: same chain the terminal walks, for the same reason — each
      // hop's transport tunnels through the previous hop's client.
      SSHClient? viaClient;
      final jumpChain = host.jumpHostId == null
          ? const <HostModel>[]
          : await planner.resolveJumpChain(host);
      for (final jumpHost in jumpChain) {
        final jumpIdentity = jumpHost.identityId == null
            ? null
            : await readIdentity(jumpHost.identityId!);
        final jumpManager = createSessionManager();
        jumpManagers.add(jumpManager);
        viaClient = await jumpManager.connect(
          planner.buildConnectConfig(
            jumpHost,
            jumpIdentity,
            onHostKeyPrompt: onHostKeyPrompt,
          ),
          viaClient: viaClient,
        );
      }

      final manager = createSessionManager();
      final client = await manager.connect(
        planner.buildConnectConfig(
          host,
          identity,
          onHostKeyPrompt: onHostKeyPrompt,
        ),
        viaClient: viaClient,
      );

      final session = _PooledSession(
        manager: manager,
        jumpManagers: jumpManagers,
      );
      // A dropped keep-alive means this pooled client is gone. Forget it here
      // so the next start dials a fresh one instead of handing out a corpse;
      // the forwards riding on it surface their own failure through the
      // engine.
      session.clientChangesSub = manager.clientChanges.listen((c) {
        if (c == null || c.isClosed) {
          unawaited(_closeSession(host.id));
        }
      });
      _sessions[host.id] = session;
      return client;
    } catch (_) {
      // A half-built chain would otherwise keep its hops (and their keep-alive
      // timers) alive forever with nothing referencing them.
      for (final manager in jumpManagers) {
        await manager.close();
      }
      rethrow;
    }
  }

  /// Gives up [ruleId]'s claim on whatever session it was using, closing that
  /// session once no rule is left on it.
  Future<void> release(String ruleId) async {
    for (final entry in _sessions.entries.toList()) {
      if (!entry.value.ruleIds.remove(ruleId)) continue;
      if (entry.value.ruleIds.isEmpty) {
        await _closeSession(entry.key);
      }
      return;
    }
  }

  Future<void> _closeSession(String hostId) async {
    final session = _sessions.remove(hostId);
    if (session == null) return;
    await session.clientChangesSub?.cancel();
    await session.manager.close();
    for (final manager in session.jumpManagers.reversed) {
      await manager.close();
    }
  }

  Future<void> dispose() async {
    for (final hostId in _sessions.keys.toList()) {
      await _closeSession(hostId);
    }
    _pending.clear();
  }
}

class _PooledSession {
  final SSHSessionManager manager;
  final List<SSHSessionManager> jumpManagers;
  final Set<String> ruleIds = {};

  /// Cancelled by [TunnelSshPool._closeSession], which owns this session's
  /// teardown — the lint only sees the scope the subscription is created in.
  // ignore: cancel_subscriptions
  StreamSubscription<SSHClient?>? clientChangesSub;

  _PooledSession({required this.manager, required this.jumpManagers});
}
