import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../../../shared/providers/workspace_provider.dart';
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

  /// Saves a new host and returns it, so a caller that offered to connect
  /// after saving has something to connect to.
  Future<HostModel> addHost({
    required String workspaceId,
    String? groupId,
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
  }) async {
    final previousState = state;
    try {
      final repo = ref.read(hostsRepositoryProvider);
      final saved = await repo.saveHost(
        workspaceId: workspaceId,
        groupId: groupId,
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
      );
      final items = await repo.getHostsByWorkspace(
        ref.read(activeWorkspaceIdProvider),
      );
      state = AsyncData(items);
      return saved;
    } catch (_) {
      state = previousState;
      // Rethrow so form dialogs can surface the failure instead of popping
      // "success" while the host was never persisted.
      rethrow;
    }
  }

  Future<void> updateHost({
    required String id,
    required String workspaceId,
    String? groupId,
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
  }) async {
    final previousState = state;
    try {
      final repo = ref.read(hostsRepositoryProvider);
      await repo.saveHost(
        id: id,
        workspaceId: workspaceId,
        groupId: groupId,
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
      );
      final items = await repo.getHostsByWorkspace(
        ref.read(activeWorkspaceIdProvider),
      );
      state = AsyncData(items);
    } catch (_) {
      state = previousState;
      // See addHost: rethrow so the edit dialog reports the failure.
      rethrow;
    }
  }

  /// Binds [hostIds] to [identityId] in one write, then refreshes the list.
  ///
  /// A null [identityId] detaches them. Returns the number of hosts changed so
  /// the caller can report it.
  Future<int> assignIdentityToHosts(
    List<String> hostIds,
    String? identityId,
  ) async {
    final previousState = state;
    try {
      final repo = ref.read(hostsRepositoryProvider);
      final changed = await repo.assignIdentityToHosts(hostIds, identityId);
      final items = await repo.getHostsByWorkspace(
        ref.read(activeWorkspaceIdProvider),
      );
      state = AsyncData(items);
      return changed;
    } catch (_) {
      state = previousState;
      // See addHost: the caller shows the failure rather than a silent no-op.
      rethrow;
    }
  }

  /// Moves every host bound to [fromIdentityId] onto [toIdentityId].
  ///
  /// Called before deleting an identity: the hosts' foreign key is
  /// `ON DELETE SET NULL`, so the binding cannot be recovered afterwards.
  Future<int> reassignIdentity(
    String fromIdentityId,
    String? toIdentityId,
  ) async {
    final previousState = state;
    try {
      final repo = ref.read(hostsRepositoryProvider);
      final changed = await repo.reassignIdentity(fromIdentityId, toIdentityId);
      final items = await repo.getHostsByWorkspace(
        ref.read(activeWorkspaceIdProvider),
      );
      state = AsyncData(items);
      return changed;
    } catch (_) {
      state = previousState;
      rethrow;
    }
  }

  Future<void> deleteHost(String id) async {
    final previousState = state;
    try {
      final repo = ref.read(hostsRepositoryProvider);
      await repo.deleteHost(id);
      final items = await repo.getHostsByWorkspace(
        ref.read(activeWorkspaceIdProvider),
      );
      state = AsyncData(items);
    } catch (_) {
      state = previousState;
    }
  }
}
