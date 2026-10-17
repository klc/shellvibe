import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/hosts_repository.dart';
import '../../domain/models/host_group_model.dart';
import '../../../workspaces/presentation/providers/workspace_provider.dart';
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

  /// Runs [op] against the repository and reloads the list. On failure the
  /// previous list is restored and the error rethrown, so the form dialog or
  /// screen can report it instead of the write looking like it worked.
  Future<void> _mutate(Future<void> Function(HostsRepository repo) op) async {
    final previousState = state;
    try {
      final repo = ref.read(hostsRepositoryProvider);
      await op(repo);
      state = AsyncData(
        await repo.getHostGroupsByWorkspace(
          ref.read(activeWorkspaceIdProvider),
        ),
      );
    } catch (_) {
      state = previousState;
      rethrow;
    }
  }

  Future<void> addGroup({
    required String workspaceId,
    String? parentId,
    required String name,
    String? colorTag,
  }) {
    return _mutate(
      (repo) => repo.saveHostGroup(
        workspaceId: workspaceId,
        parentId: parentId,
        name: name,
        colorTag: colorTag,
      ),
    );
  }

  Future<void> updateGroup({
    required String id,
    required String workspaceId,
    String? parentId,
    required String name,
    String? colorTag,
  }) {
    return _mutate(
      (repo) => repo.saveHostGroup(
        id: id,
        workspaceId: workspaceId,
        parentId: parentId,
        name: name,
        colorTag: colorTag,
      ),
    );
  }

  Future<void> deleteGroup(String id) {
    return _mutate((repo) async {
      await repo.deleteHostGroup(id);
      // The database dropped this tag from every host that carried it; the
      // cached host list still names it.
      ref.invalidate(hostsProvider);
    });
  }
}
