import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/presentation/notifiers/settings_notifier.dart';
import '../../features/workspaces/data/repositories/workspace_repository.dart';
import '../../features/workspaces/domain/models/workspace_model.dart';
import 'database_providers.dart';

final workspacesProvider = FutureProvider<List<WorkspaceModel>>((ref) {
  final repository = WorkspaceRepository(
    ref.watch(appDatabaseProvider).workspacesDao,
  );
  return repository.getWorkspaces();
});

class ActiveWorkspaceIdNotifier extends Notifier<String> {
  @override
  String build() {
    final settings = ref.watch(settingsProvider);
    final workspaces = ref.watch(workspacesProvider).value;
    final savedId = settings.value?.activeWorkspaceId ?? 'default';

    if (workspaces == null ||
        workspaces.any((workspace) => workspace.id == savedId)) {
      return savedId;
    }

    return 'default';
  }

  Future<void> select(String workspaceId) async {
    final workspaces = ref.read(workspacesProvider).value;
    if (workspaces != null &&
        !workspaces.any((workspace) => workspace.id == workspaceId)) {
      return;
    }
    if (state == workspaceId) return;

    state = workspaceId;
    await ref.read(settingsProvider.notifier).setActiveWorkspace(workspaceId);
  }
}

final activeWorkspaceIdProvider =
    NotifierProvider<ActiveWorkspaceIdNotifier, String>(
      ActiveWorkspaceIdNotifier.new,
    );
