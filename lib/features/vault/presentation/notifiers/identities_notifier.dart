import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../data/repositories/vault_repository.dart';
import '../../domain/models/identity_model.dart';

part 'identities_notifier.g.dart';

@riverpod
VaultRepository vaultRepository(VaultRepositoryRef ref) {
  final dao = ref.watch(identitiesDaoProvider);
  final crypto = ref.watch(encryptionEngineProvider);
  final storage = ref.watch(secureStorageServiceProvider);
  return VaultRepository(
    identitiesDao: dao,
    encryptionEngine: crypto,
    secureStorageService: storage,
  );
}

@riverpod
class IdentitiesNotifier extends _$IdentitiesNotifier {
  @override
  Future<List<IdentityModel>> build() async {
    final repo = ref.watch(vaultRepositoryProvider);
    return await repo.getAllIdentities(decryptSecrets: false);
  }

  Future<void> addIdentity({
    required String workspaceId,
    required String title,
    required String username,
    required String authType,
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(vaultRepositoryProvider);
      await repo.saveIdentity(
        workspaceId: workspaceId,
        title: title,
        username: username,
        authType: authType,
        password: password,
        privateKey: privateKey,
        passphrase: passphrase,
      );
      return await repo.getAllIdentities(decryptSecrets: false);
    });
  }

  Future<void> updateIdentity({
    required String id,
    required String workspaceId,
    required String title,
    required String username,
    required String authType,
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(vaultRepositoryProvider);
      await repo.saveIdentity(
        id: id,
        workspaceId: workspaceId,
        title: title,
        username: username,
        authType: authType,
        password: password,
        privateKey: privateKey,
        passphrase: passphrase,
      );
      return await repo.getAllIdentities(decryptSecrets: false);
    });
  }

  Future<void> deleteIdentity(String id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(vaultRepositoryProvider);
      await repo.deleteIdentity(id);
      return await repo.getAllIdentities(decryptSecrets: false);
    });
  }

  Future<IdentityModel?> getDecryptedIdentity(String id) async {
    final repo = ref.read(vaultRepositoryProvider);
    return await repo.getIdentityById(id, decryptSecrets: true);
  }
}
