import 'package:dartssh2/dartssh2.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/network/tunnel_engine.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/domain/services/ssh_connect_planner.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../../terminal/domain/models/terminal_tab_session.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../data/repositories/tunnel_repository_impl.dart';
import '../../domain/models/tunnel_rule_model.dart';
import '../../domain/repositories/tunnel_repository.dart';
import '../../domain/services/tunnel_ssh_pool.dart';

part 'tunnels_providers.g.dart';

/// Provider for [TunnelRepository]
@riverpod
TunnelRepository tunnelRepository(Ref ref) {
  final dao = ref.watch(tunnelsDaoProvider);
  return TunnelRepositoryImpl(dao);
}

/// Provider for [TunnelEngine]
@Riverpod(keepAlive: true)
TunnelEngine tunnelEngine(Ref ref) {
  final engine = TunnelEngine();
  ref.onDispose(() {
    engine.dispose();
  });
  return engine;
}

/// Provider for [TunnelSshPool].
///
/// `keepAlive` for the same reason [tunnelEngineProvider] is: the connections
/// it holds outlive whatever screen started them, and an auto-disposing pool
/// would drop a live forward's transport the moment the Tunnels screen was
/// popped.
@Riverpod(keepAlive: true)
TunnelSshPool tunnelSshPool(Ref ref) {
  final pool = TunnelSshPool(
    planner: SshConnectPlanner(ref.read(hostsRepositoryProvider)),
    createSessionManager: () =>
        SSHSessionManager(knownHostsDao: ref.read(knownHostsDaoProvider)),
    readIdentity: (identityId) =>
        ref.read(vaultRepositoryProvider).getIdentityById(identityId),
  );
  ref.onDispose(pool.dispose);
  return pool;
}

/// Stream provider for active tunnels from [TunnelEngine]
@riverpod
Stream<List<ActiveTunnel>> activeTunnelsStream(Ref ref) {
  final engine = ref.watch(tunnelEngineProvider);
  return engine.watchActiveTunnels();
}

/// State for TunnelsScreen
class TunnelsState {
  final List<TunnelRuleModel> rules;
  final bool isLoading;
  final String? error;

  const TunnelsState({
    this.rules = const [],
    this.isLoading = false,
    this.error,
  });

  TunnelsState copyWith({
    List<TunnelRuleModel>? rules,
    bool? isLoading,
    String? error,
  }) {
    return TunnelsState(
      rules: rules ?? this.rules,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

@riverpod
class TunnelsNotifier extends _$TunnelsNotifier {
  /// Set when the autoDispose notifier is torn down; the deferred load in
  /// [build] must not write state after disposal (no `ref.mounted` in 2.x).
  bool _disposed = false;

  @override
  TunnelsState build() {
    ref.watch(activeWorkspaceIdProvider);
    ref.onDispose(() => _disposed = true);
    // Initial fetch of rules
    Future.microtask(() => loadRules());
    return const TunnelsState(isLoading: true);
  }

  Future<void> loadRules([String? hostId]) async {
    if (_disposed) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final repository = ref.read(tunnelRepositoryProvider);
      final rules = hostId != null
          ? await repository.getRulesForHost(hostId)
          : await repository.getRulesByWorkspace(
              ref.read(activeWorkspaceIdProvider),
            );
      if (_disposed) return;
      state = state.copyWith(rules: rules, isLoading: false);
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> addRule(TunnelRuleModel rule) async {
    if (_disposed) return;
    try {
      final repository = ref.read(tunnelRepositoryProvider);
      await repository.addRule(rule);
      await loadRules();
    } catch (e) {
      if (_disposed) rethrow;
      state = state.copyWith(error: 'Failed to add rule: $e');
      // Rethrow so the calling screen can toast the failure instead of
      // silently closing as if the rule was saved.
      rethrow;
    }
  }

  Future<void> updateRule(TunnelRuleModel rule) async {
    if (_disposed) return;
    try {
      final repository = ref.read(tunnelRepositoryProvider);
      await repository.updateRule(rule);
      await loadRules();
    } catch (e) {
      if (_disposed) rethrow;
      state = state.copyWith(error: 'Failed to update rule: $e');
      rethrow;
    }
  }

  Future<void> deleteRule(String id) async {
    if (_disposed) return;
    try {
      await ref.read(tunnelEngineProvider).stopTunnel(id);
      await ref.read(tunnelSshPoolProvider).release(id);
      final repository = ref.read(tunnelRepositoryProvider);
      await repository.deleteRule(id);
      await loadRules();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(error: 'Failed to delete rule: $e');
    }
  }

  /// Starts [rule], opening the SSH connection it rides on if nothing else
  /// has one already.
  ///
  /// A forward needs an authenticated client and nothing more, so this no
  /// longer demands that the user first open (and keep open) a terminal
  /// session. In order of preference it uses:
  ///
  /// 1. a connected terminal tab **for this rule's host** — reusing a session
  ///    the user already has costs nothing, and matching on the host is a fix
  ///    in itself: the screen used to hand over whatever tab happened to be
  ///    active, so a rule for host A could quietly tunnel through host B;
  /// 2. a background connection this pool already holds for that host;
  /// 3. a new background connection, dialed here.
  ///
  /// [resolveIdentity] is how a caller with a `BuildContext` offers to ask for
  /// credentials a host has none stored for (`None — Prompt on Connect`).
  /// Without it, such a host simply fails rather than connecting anonymously.
  /// Throws on failure so the caller can report it; [state] carries the same
  /// message for anything watching.
  Future<void> startRule(
    TunnelRuleModel rule, {
    Future<({bool ok, IdentityModel? identity})> Function(HostModel host)?
    resolveIdentity,
    HostKeyPromptCallback? onHostKeyPrompt,
  }) async {
    if (_disposed) return;
    final engine = ref.read(tunnelEngineProvider);
    final pool = ref.read(tunnelSshPoolProvider);

    final SSHClient sshClient;
    try {
      final reusable = _liveTerminalClientFor(rule.hostId);
      if (reusable != null) {
        sshClient = reusable;
      } else {
        final host = await ref
            .read(hostsRepositoryProvider)
            .getHostById(rule.hostId);
        if (host == null) {
          throw StateError(
            'The host this forward belongs to no longer exists.',
          );
        }

        IdentityModel? identity;
        if (host.identityId != null) {
          identity = await ref
              .read(vaultRepositoryProvider)
              .getIdentityById(host.identityId!);
        } else if (resolveIdentity != null) {
          final resolved = await resolveIdentity(host);
          // Cancelled: the user called the connection off, which is not a
          // failure to report.
          if (!resolved.ok) return;
          identity = resolved.identity;
        }

        sshClient = await pool.acquire(
          ruleId: rule.id,
          host: host,
          identity: identity,
          onHostKeyPrompt: onHostKeyPrompt,
        );
      }
    } catch (e) {
      if (!_disposed) {
        state = state.copyWith(error: 'Failed to connect: $e');
      }
      rethrow;
    }

    try {
      if (rule.type == 'local') {
        await engine.startLocalForward(
          ruleId: rule.id,
          hostId: rule.hostId,
          sshClient: sshClient,
          localPort: rule.localPort,
          remoteHost: rule.remoteHost ?? '127.0.0.1',
          remotePort: rule.remotePort ?? 80,
        );
      } else if (rule.type == 'remote') {
        await engine.startRemoteForward(
          ruleId: rule.id,
          hostId: rule.hostId,
          sshClient: sshClient,
          remotePort: rule.remotePort ?? 8080,
          localHost: rule.localHost ?? '127.0.0.1',
          localPort: rule.localPort,
        );
      } else if (rule.type == 'dynamic') {
        await engine.startDynamicForward(
          ruleId: rule.id,
          hostId: rule.hostId,
          sshClient: sshClient,
          localPort: rule.localPort,
        );
      }
    } catch (e) {
      // The forward never came up, so nothing is riding on the connection any
      // more — hand the claim back so a pool-owned session does not stay open
      // for a rule that failed.
      await pool.release(rule.id);
      if (!_disposed) {
        state = state.copyWith(error: 'Failed to start tunnel: $e');
      }
      rethrow;
    }
  }

  Future<void> stopRule(String id) async {
    final engine = ref.read(tunnelEngineProvider);
    await engine.stopTunnel(id);
    await ref.read(tunnelSshPoolProvider).release(id);
  }

  /// A connected terminal tab's client for [hostId], or null when no tab is
  /// currently on that host.
  SSHClient? _liveTerminalClientFor(String hostId) {
    for (final tab in ref.read(terminalTabsProvider).tabs) {
      if (tab.sessionType != TerminalSessionType.ssh) continue;
      if (tab.host?.id != hostId) continue;
      final client = tab.sshSessionManager?.client;
      if (client != null && !client.isClosed) return client;
    }
    return null;
  }
}
