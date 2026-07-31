import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../data/repositories/runbooks_repository.dart';
import '../../domain/models/runbook_model.dart';
import '../../domain/models/runbook_step_model.dart';
import '../../domain/services/runbook_executor.dart';

part 'runbooks_notifier.g.dart';

@riverpod
RunbooksRepository runbooksRepository(RunbooksRepositoryRef ref) {
  final dao = ref.watch(runbooksDaoProvider);
  return RunbooksRepository(dao);
}

@riverpod
RunbookExecutor runbookExecutor(RunbookExecutorRef ref) {
  return RunbookExecutor();
}

@riverpod
class RunbooksNotifier extends _$RunbooksNotifier {
  @override
  Future<List<RunbookModel>> build() async {
    final repo = ref.watch(runbooksRepositoryProvider);
    return await repo.getAllRunbooks();
  }

  Future<void> addRunbook({
    required String workspaceId,
    required String title,
    String? description,
    List<RunbookStepModel> steps = const [],
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
        createdAt: DateTime.now(),
      );
      await repo.addRunbook(runbook);
      return await repo.getAllRunbooks();
    });
  }

  Future<void> updateRunbook(RunbookModel runbook) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(runbooksRepositoryProvider);
      await repo.updateRunbook(runbook);
      return await repo.getAllRunbooks();
    });
  }

  Future<void> deleteRunbook(String id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(runbooksRepositoryProvider);
      await repo.deleteRunbook(id);
      return await repo.getAllRunbooks();
    });
  }

  Future<RunbookExecutionResult> executeRunbook(
    RunbookModel runbook,
    Future<String> Function(String command, int timeoutSeconds) commandRunner, {
    Map<String, String> variableValues = const {},
    void Function(RunbookStepModel step, String status)? onProgress,
  }) async {
    final executor = ref.read(runbookExecutorProvider);
    return await executor.executeRunbook(
      runbook,
      commandRunner,
      variableValues: variableValues,
      onProgress: onProgress,
    );
  }
}
