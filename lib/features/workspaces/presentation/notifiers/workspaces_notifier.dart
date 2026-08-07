import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/database/models/workspace_usage.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../data/repositories/workspace_repository.dart';
import '../../domain/models/workspace_model.dart';

part 'workspaces_notifier.g.dart';

@riverpod
WorkspaceRepository workspaceRepository(Ref ref) {
  return WorkspaceRepository(ref.watch(appDatabaseProvider).workspacesDao);
}

/// Must be [Riverpod(keepAlive: true)]: every call site only does
/// `ref.read(...notifier)`, never `watch`, so with autoDispose this has
/// zero listeners and gets torn down mid-`await`, leaving `create`/`rename`/
/// `delete` mutating a disposed ref.
@Riverpod(keepAlive: true)
class WorkspaceManagerNotifier extends _$WorkspaceManagerNotifier {
  @override
  Future<List<WorkspaceModel>> build() async {
    return ref.watch(workspaceRepositoryProvider).getWorkspaces();
  }

  Future<void> create(String name) async {
    final repository = ref.read(workspaceRepositoryProvider);
    await repository.createWorkspace(name);
    ref.invalidate(workspacesProvider);
    state = AsyncData(await repository.getWorkspaces());
  }

  Future<void> rename(String id, String name) async {
    final repository = ref.read(workspaceRepositoryProvider);
    await repository.renameWorkspace(id, name);
    ref.invalidate(workspacesProvider);
    state = AsyncData(await repository.getWorkspaces());
  }

  Future<void> delete(String id) async {
    final repository = ref.read(workspaceRepositoryProvider);
    await repository.deleteWorkspace(id);
    ref.invalidate(workspacesProvider);
    state = AsyncData(await repository.getWorkspaces());
  }

  Future<WorkspaceUsage> getUsage(String id) {
    return ref.read(workspaceRepositoryProvider).getUsage(id);
  }
}
