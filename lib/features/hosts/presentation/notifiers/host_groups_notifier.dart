import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/host_group_model.dart';
import '../../../../shared/providers/workspace_provider.dart';
import 'hosts_notifier.dart';

part 'host_groups_notifier.g.dart';

@riverpod
class HostGroupsNotifier extends _$HostGroupsNotifier {
  @override
  Future<List<HostGroupModel>> build() async {
    final repo = ref.watch(hostsRepositoryProvider);
    return await repo.getHostGroupsByWorkspace(
      ref.watch(activeWorkspaceIdProvider),
    );
  }

  Future<void> addGroup({
    required String workspaceId,
    String? parentId,
    required String name,
    String? colorTag,
  }) async {
    final previousState = state;
    try {
      final repo = ref.read(hostsRepositoryProvider);
      await repo.saveHostGroup(
        workspaceId: workspaceId,
        parentId: parentId,
        name: name,
        colorTag: colorTag,
      );
      final items = await repo.getHostGroupsByWorkspace(
        ref.read(activeWorkspaceIdProvider),
      );
      state = AsyncData(items);
    } catch (_) {
      state = previousState;
      // Rethrow so the form dialog can report the failure instead of popping
      // "success" while the group was never persisted.
      rethrow;
    }
  }

  Future<void> updateGroup({
    required String id,
    required String workspaceId,
    String? parentId,
    required String name,
    String? colorTag,
  }) async {
    final previousState = state;
    try {
      final repo = ref.read(hostsRepositoryProvider);
      await repo.saveHostGroup(
        id: id,
        workspaceId: workspaceId,
        parentId: parentId,
        name: name,
        colorTag: colorTag,
      );
      final items = await repo.getHostGroupsByWorkspace(
        ref.read(activeWorkspaceIdProvider),
      );
      state = AsyncData(items);
    } catch (_) {
      state = previousState;
      rethrow;
    }
  }

  Future<void> deleteGroup(String id) async {
    final previousState = state;
    try {
      final repo = ref.read(hostsRepositoryProvider);
      await repo.deleteHostGroup(id);
      state = AsyncData(
        await repo.getHostGroupsByWorkspace(
          ref.read(activeWorkspaceIdProvider),
        ),
      );
    } catch (_) {
      state = previousState;
    }
  }
}
