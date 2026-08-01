import 'package:dartssh2/dartssh2.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/network/tunnel_engine.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../data/repositories/tunnel_repository_impl.dart';
import '../../domain/models/tunnel_rule_model.dart';
import '../../domain/repositories/tunnel_repository.dart';

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
          : await repository.getAllRules();
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
      final repository = ref.read(tunnelRepositoryProvider);
      await repository.deleteRule(id);
      await loadRules();
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(error: 'Failed to delete rule: $e');
    }
  }

  Future<void> startRule(TunnelRuleModel rule, SSHClient sshClient) async {
    if (_disposed) return;
    final engine = ref.read(tunnelEngineProvider);
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
      if (_disposed) return;
      state = state.copyWith(error: 'Failed to start tunnel: $e');
    }
  }

  Future<void> stopRule(String id) async {
    final engine = ref.read(tunnelEngineProvider);
    await engine.stopTunnel(id);
  }
}
