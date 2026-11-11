import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../../workspaces/presentation/providers/workspace_provider.dart';
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

  /// Runs [op], then reloads the list in place: an add, edit or delete must
  /// not blank the list to a spinner on the way through, and saving default
  /// hosts happens as a run starts and must not blank it under the run.
  ///
  /// A failed [op] throws to the caller, which has to say the save did not
  /// happen, and leaves the list as it was: it is a write that failed, not
  /// the list.
  Future<void> _mutate(Future<void> Function() op) async {
    await op();
    state = await AsyncValue.guard(
      () => ref
          .read(runbooksRepositoryProvider)
          .getRunbooksByWorkspace(ref.read(activeWorkspaceIdProvider)),
    );
  }

  Future<void> addRunbook({
    required String workspaceId,
    required String title,
    String? description,
    List<RunbookStepModel> steps = const [],
    List<VariableDeclaration> variables = const [],
    List<String> tags = const [],
  }) => _mutate(
    () => ref
        .read(runbooksRepositoryProvider)
        .addRunbook(
          RunbookModel(
            id: const Uuid().v4(),
            workspaceId: workspaceId,
            title: title,
            description: description,
            steps: steps,
            variables: variables,
            tags: tags,
            createdAt: DateTime.now(),
          ),
        ),
  );

  Future<void> updateRunbook(RunbookModel runbook) => _mutate(
    () => ref.read(runbooksRepositoryProvider).updateRunbook(runbook),
  );

  Future<void> deleteRunbook(String id) =>
      _mutate(() => ref.read(runbooksRepositoryProvider).deleteRunbook(id));

  /// Saves the hosts the target sheet preselects for [runbookId].
  Future<void> setDefaultHostIds(String runbookId, List<String> hostIds) =>
      _mutate(
        () => ref
            .read(runbooksRepositoryProvider)
            .setDefaultHostIds(runbookId, hostIds),
      );
}
