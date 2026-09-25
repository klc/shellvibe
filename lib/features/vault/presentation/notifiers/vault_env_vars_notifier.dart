import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../data/repositories/vault_env_repository.dart';
import '../../domain/models/vault_env_var.dart';
import 'identities_notifier.dart';

part 'vault_env_vars_notifier.g.dart';

@riverpod
VaultEnvRepository vaultEnvRepository(Ref ref) {
  final dao = ref.watch(vaultEnvVarsDaoProvider);
  final crypto = ref.watch(encryptionEngineProvider);
  return VaultEnvRepository(
    dao: dao,
    encryptionEngine: crypto,
    vaultKeyService: ref.watch(vaultKeyServiceProvider),
  );
}

@riverpod
class VaultEnvVarsNotifier extends _$VaultEnvVarsNotifier {
  @override
  Future<List<VaultEnvVarModel>> build() async {
    final repo = ref.watch(vaultEnvRepositoryProvider);
    return repo.list(
      workspaceId: ref.watch(activeWorkspaceIdProvider),
      decrypt: false,
    );
  }

  Future<void> addVariable({
    required String workspaceId,
    required String name,
    required String value,
  }) async {
    final previousState = state;
    try {
      final repo = ref.read(vaultEnvRepositoryProvider);
      await repo.save(workspaceId: workspaceId, name: name, value: value);
      final items = await repo.list(
        workspaceId: ref.read(activeWorkspaceIdProvider),
      );
      state = AsyncData(items);
    } catch (_) {
      state = previousState;
      // Rethrow so the caller (the add/edit form) can tell the user the save
      // failed instead of closing as if it had succeeded.
      rethrow;
    }
  }

  Future<void> updateVariable({
    required String id,
    required String workspaceId,
    required String name,
    required String value,
  }) async {
    final previousState = state;
    try {
      final repo = ref.read(vaultEnvRepositoryProvider);
      await repo.save(
        id: id,
        workspaceId: workspaceId,
        name: name,
        value: value,
      );
      final items = await repo.list(
        workspaceId: ref.read(activeWorkspaceIdProvider),
      );
      state = AsyncData(items);
    } catch (_) {
      state = previousState;
      rethrow;
    }
  }

  Future<void> deleteVariable(String id) async {
    final previousState = state;
    try {
      final repo = ref.read(vaultEnvRepositoryProvider);
      await repo.delete(id);
      final items = await repo.list(
        workspaceId: ref.read(activeWorkspaceIdProvider),
      );
      state = AsyncData(items);
    } catch (_) {
      state = previousState;
      rethrow;
    }
  }

  /// Decrypts one variable's value on demand, for the row's reveal control.
  Future<String?> decryptValue(String id) async {
    final repo = ref.read(vaultEnvRepositoryProvider);
    return repo.decryptValue(id);
  }
}
