import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../data/repositories/hosts_repository.dart';
import '../../domain/models/host_model.dart';

part 'hosts_notifier.g.dart';

@riverpod
HostsRepository hostsRepository(HostsRepositoryRef ref) {
  final dao = ref.watch(hostsDaoProvider);
  return HostsRepository(hostsDao: dao);
}

@riverpod
class HostsNotifier extends _$HostsNotifier {
  @override
  Future<List<HostModel>> build() async {
    final repo = ref.watch(hostsRepositoryProvider);
    return await repo.getAllHosts();
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
    state = AsyncLoading<List<HostModel>>().copyWithPrevious(previousState);
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
      final items = await repo.getAllHosts();
      state = AsyncData(items);
    } catch (e, st) {
      state = AsyncError<List<HostModel>>(e, st).copyWithPrevious(previousState);
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
    state = AsyncLoading<List<HostModel>>().copyWithPrevious(previousState);
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
      final items = await repo.getAllHosts();
      state = AsyncData(items);
    } catch (e, st) {
      state = AsyncError<List<HostModel>>(e, st).copyWithPrevious(previousState);
      // See addHost: rethrow so the edit dialog reports the failure.
      rethrow;
    }
  }

  Future<void> deleteHost(String id) async {
    final previousState = state;
    state = AsyncLoading<List<HostModel>>().copyWithPrevious(previousState);
    try {
      final repo = ref.read(hostsRepositoryProvider);
      await repo.deleteHost(id);
      final items = await repo.getAllHosts();
      state = AsyncData(items);
    } catch (e, st) {
      state = AsyncError<List<HostModel>>(e, st).copyWithPrevious(previousState);
    }
  }
}
