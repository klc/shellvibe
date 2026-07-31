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
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
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
      return await repo.getAllHosts();
    });
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
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
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
      return await repo.getAllHosts();
    });
  }

  Future<void> deleteHost(String id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(hostsRepositoryProvider);
      await repo.deleteHost(id);
      return await repo.getAllHosts();
    });
  }
}
