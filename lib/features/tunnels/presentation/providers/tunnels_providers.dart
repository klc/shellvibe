import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/network/tunnel_engine.dart';
import '../../../../shared/database/app_database.dart';
import '../../../../shared/providers/database_providers.dart';

part 'tunnels_providers.g.dart';

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
  final List<PortForwardRule> rules;
  final bool isLoading;
  final String? error;

  const TunnelsState({
    this.rules = const [],
    this.isLoading = false,
    this.error,
  });

  TunnelsState copyWith({
    List<PortForwardRule>? rules,
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
  @override
  TunnelsState build() {
    // Initial fetch of rules
    Future.microtask(() => loadRules());
    return const TunnelsState(isLoading: true);
  }

  Future<void> loadRules([String? hostId]) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final dao = ref.read(tunnelsDaoProvider);
      final rules = hostId != null
          ? await dao.getRulesForHost(hostId)
          : await (dao.select(dao.portForwardRules)).get();
      state = state.copyWith(rules: rules, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> addRule(PortForwardRulesCompanion rule) async {
    try {
      final dao = ref.read(tunnelsDaoProvider);
      await dao.insertRule(rule);
      await loadRules();
    } catch (e) {
      state = state.copyWith(error: 'Failed to add rule: $e');
    }
  }

  Future<void> updateRule(PortForwardRule rule) async {
    try {
      final dao = ref.read(tunnelsDaoProvider);
      await dao.updateRule(rule);
      await loadRules();
    } catch (e) {
      state = state.copyWith(error: 'Failed to update rule: $e');
    }
  }

  Future<void> deleteRule(String id) async {
    try {
      await ref.read(tunnelEngineProvider).stopTunnel(id);
      final dao = ref.read(tunnelsDaoProvider);
      await dao.deleteRule(id);
      await loadRules();
    } catch (e) {
      state = state.copyWith(error: 'Failed to delete rule: $e');
    }
  }

  Future<void> startRule(PortForwardRule rule, SSHClient sshClient) async {
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
          localHost: rule.remoteHost ?? '127.0.0.1',
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
      state = state.copyWith(error: 'Failed to start tunnel: $e');
    }
  }

  Future<void> stopRule(String id) async {
    final engine = ref.read(tunnelEngineProvider);
    await engine.stopTunnel(id);
  }
}
