import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/host_group_model.dart';
import 'hosts_notifier.dart';

part 'host_groups_notifier.g.dart';

@riverpod
class HostGroupsNotifier extends _$HostGroupsNotifier {
  @override
  Future<List<HostGroupModel>> build() async {
    final repo = ref.watch(hostsRepositoryProvider);
    return await repo.getAllHostGroups();
  }

  Future<void> addGroup({
    required String workspaceId,
    String? parentId,
    required String name,
    String? colorTag,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(hostsRepositoryProvider);
      await repo.saveHostGroup(
        workspaceId: workspaceId,
        parentId: parentId,
        name: name,
        colorTag: colorTag,
      );
      return await repo.getAllHostGroups();
    });
  }

  Future<void> updateGroup({
    required String id,
    required String workspaceId,
    String? parentId,
    required String name,
    String? colorTag,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(hostsRepositoryProvider);
      await repo.saveHostGroup(
        id: id,
        workspaceId: workspaceId,
        parentId: parentId,
        name: name,
        colorTag: colorTag,
      );
      return await repo.getAllHostGroups();
    });
  }

  Future<void> deleteGroup(String id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(hostsRepositoryProvider);
      await repo.deleteHostGroup(id);
      return await repo.getAllHostGroups();
    });
  }
}
