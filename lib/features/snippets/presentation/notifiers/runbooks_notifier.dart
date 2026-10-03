import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../data/repositories/runbooks_repository.dart';
import '../../domain/models/runbook_model.dart';
import '../../domain/models/runbook_step_model.dart';
import '../../domain/models/variable_declaration.dart';

part 'runbooks_notifier.g.dart';

@riverpod
RunbooksRepository runbooksRepository(Ref ref) {
  final dao = ref.watch(runbooksDaoProvider);
  return RunbooksRepository(dao);
}

@riverpod
class RunbooksNotifier extends _$RunbooksNotifier {
  @override
  Future<List<RunbookModel>> build() async {
    final repo = ref.watch(runbooksRepositoryProvider);
    return await repo.getRunbooksByWorkspace(
      ref.watch(activeWorkspaceIdProvider),
    );
  }

  Future<void> addRunbook({
    required String workspaceId,
    required String title,
    String? description,
    List<RunbookStepModel> steps = const [],
    List<VariableDeclaration> variables = const [],
    List<String> tags = const [],
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(runbooksRepositoryProvider);
      final runbook = RunbookModel(
        id: const Uuid().v4(),
        workspaceId: workspaceId,
        title: title,
        description: description,
        steps: steps,
        variables: variables,
        tags: tags,
        createdAt: DateTime.now(),
      );
      await repo.addRunbook(runbook);
      return await repo.getRunbooksByWorkspace(
        ref.read(activeWorkspaceIdProvider),
      );
    });
  }

  Future<void> updateRunbook(RunbookModel runbook) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(runbooksRepositoryProvider);
      await repo.updateRunbook(runbook);
      return await repo.getRunbooksByWorkspace(
        ref.read(activeWorkspaceIdProvider),
      );
    });
  }

  Future<void> deleteRunbook(String id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(runbooksRepositoryProvider);
      await repo.deleteRunbook(id);
      return await repo.getRunbooksByWorkspace(
        ref.read(activeWorkspaceIdProvider),
      );
    });
  }

  /// Saves the hosts the target sheet preselects for [runbookId]. Reloads in
  /// place, without the loading state the editor's writes pass through: this
  /// happens as a run starts and must not blank the list under it.
  Future<void> setDefaultHostIds(String runbookId, List<String> hostIds) async {
    final repo = ref.read(runbooksRepositoryProvider);
    await repo.setDefaultHostIds(runbookId, hostIds);
    state = AsyncData(
      await repo.getRunbooksByWorkspace(ref.read(activeWorkspaceIdProvider)),
    );
  }
}
