import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../../workspaces/presentation/providers/workspace_provider.dart';
import '../../data/repositories/hosts_repository.dart';
import '../../domain/models/host_model.dart';

part 'hosts_notifier.g.dart';

@riverpod
HostsRepository hostsRepository(Ref ref) {
  final dao = ref.watch(hostsDaoProvider);
  return HostsRepository(hostsDao: dao);
}

@riverpod
class HostsNotifier extends _$HostsNotifier {
  @override
  Future<List<HostModel>> build() async {
    final repo = ref.watch(hostsRepositoryProvider);
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    return await repo.getHostsByWorkspace(workspaceId);
  }

  /// Runs [op] against the repository and reloads the list. On failure the
  /// previous list is restored and the error rethrown, so a form dialog can
  /// surface it instead of popping "success" while nothing was persisted.
  Future<T> _mutate<T>(Future<T> Function(HostsRepository repo) op) async {
    final previousState = state;
    try {
      final repo = ref.read(hostsRepositoryProvider);
      final result = await op(repo);
      state = AsyncData(
        await repo.getHostsByWorkspace(ref.read(activeWorkspaceIdProvider)),
      );
      return result;
    } catch (_) {
      state = previousState;
      rethrow;
    }
  }

  /// Saves a new host and returns it, so a caller that offered to connect
  /// after saving has something to connect to.
  Future<HostModel> addHost({
    required String workspaceId,
    List<String> groupIds = const [],
    String? identityId,
    required String label,
    required String hostname,
    String? username,
    int port = 22,
    String protocol = 'ssh',
    String? moshServerPath,
    String? moshPortRange,
    String? colorTag,
    String? jumpHostId,
    String? startupSnippetId,
    bool mcpVisible = true,
    String mcpMaxMode = 'guarded',
  }) {
    return _mutate(
      (repo) => repo.saveHost(
        workspaceId: workspaceId,
        groupIds: groupIds,
        identityId: identityId,
        label: label,
        hostname: hostname,
        username: username,
        port: port,
        protocol: protocol,
        moshServerPath: moshServerPath,
        moshPortRange: moshPortRange,
        colorTag: colorTag,
        jumpHostId: jumpHostId,
        startupSnippetId: startupSnippetId,
        mcpVisible: mcpVisible,
        mcpMaxMode: mcpMaxMode,
      ),
    );
  }

  Future<void> updateHost({
    required String id,
    required String workspaceId,
    List<String> groupIds = const [],
    String? identityId,
    required String label,
    required String hostname,
    String? username,
    int port = 22,
    String protocol = 'ssh',
    String? moshServerPath,
    String? moshPortRange,
    String? colorTag,
    String? jumpHostId,
    String? startupSnippetId,
    bool mcpVisible = true,
    String mcpMaxMode = 'guarded',
  }) {
    return _mutate(
      (repo) => repo.saveHost(
        id: id,
        workspaceId: workspaceId,
        groupIds: groupIds,
        identityId: identityId,
        label: label,
        hostname: hostname,
        username: username,
        port: port,
        protocol: protocol,
        moshServerPath: moshServerPath,
        moshPortRange: moshPortRange,
        colorTag: colorTag,
        jumpHostId: jumpHostId,
        startupSnippetId: startupSnippetId,
        mcpVisible: mcpVisible,
        mcpMaxMode: mcpMaxMode,
      ),
    );
  }

  /// Binds [hostIds] to [identityId] in one write, then refreshes the list.
  ///
  /// A null [identityId] detaches them. Returns the number of hosts changed so
  /// the caller can report it.
  Future<int> assignIdentityToHosts(List<String> hostIds, String? identityId) {
    return _mutate((repo) => repo.assignIdentityToHosts(hostIds, identityId));
  }

  /// Moves every host bound to [fromIdentityId] onto [toIdentityId].
  ///
  /// Called before deleting an identity: the hosts' foreign key is
  /// `ON DELETE SET NULL`, so the binding cannot be recovered afterwards.
  Future<int> reassignIdentity(String fromIdentityId, String? toIdentityId) {
    return _mutate(
      (repo) => repo.reassignIdentity(fromIdentityId, toIdentityId),
    );
  }

  Future<void> deleteHost(String id) {
    return _mutate((repo) => repo.deleteHost(id));
  }
}
