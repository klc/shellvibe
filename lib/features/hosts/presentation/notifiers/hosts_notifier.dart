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

  Future<void> addHost({
    required String workspaceId,
    String? groupId,
    String? identityId,
    required String label,
    required String hostname,
    String? username,
    int port = 22,
    String protocol = 'ssh',
    String? colorTag,
    String? jumpHostId,
  }) async {
    final previousState = state;
    try {
      final repo = ref.read(hostsRepositoryProvider);
      await repo.saveHost(
        workspaceId: workspaceId,
        groupId: groupId,
        identityId: identityId,
        label: label,
        hostname: hostname,
        username: username,
        port: port,
        protocol: protocol,
        colorTag: colorTag,
        jumpHostId: jumpHostId,
      );
      final items = await repo.getHostsByWorkspace(
        ref.read(activeWorkspaceIdProvider),
      );
      state = AsyncData(items);
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
