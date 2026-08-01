import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../../../core/sync/e2ee_cloud_sync_service.dart';
import '../../data/repositories/vault_repository.dart';
import '../../data/vault_key_service.dart';
import '../../domain/models/identity_model.dart';

part 'identities_notifier.g.dart';

/// Single app-wide owner of the vault Data Encryption Key.
///
/// Must be [Riverpod(keepAlive: true)]: the unwrapped DEK lives in this
/// instance's memory, so disposing it would silently re-lock the vault.
@Riverpod(keepAlive: true)
VaultKeyService vaultKeyService(VaultKeyServiceRef ref) {
  return VaultKeyService(
    encryptionEngine: ref.watch(encryptionEngineProvider),
    secureStorageService: ref.watch(secureStorageServiceProvider),
  );
}

/// E2EE backup service. Needs the vault key to make backups self-contained.
@riverpod
E2EECloudSyncService e2eeCloudSyncService(E2eeCloudSyncServiceRef ref) {
  return E2EECloudSyncService(
    vaultKeyService: ref.watch(vaultKeyServiceProvider),
    cryptoEngine: ref.watch(encryptionEngineProvider),
  );
}

@riverpod
VaultRepository vaultRepository(VaultRepositoryRef ref) {
  final dao = ref.watch(identitiesDaoProvider);
  final crypto = ref.watch(encryptionEngineProvider);
  return VaultRepository(
    identitiesDao: dao,
    encryptionEngine: crypto,
    vaultKeyService: ref.watch(vaultKeyServiceProvider),
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
    final previousState = state;
    state = AsyncLoading<List<IdentityModel>>().copyWithPrevious(previousState);
    try {
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
      final items = await repo.getAllIdentities(decryptSecrets: false);
      state = AsyncData(items);
    } catch (e, st) {
      state = AsyncError<List<IdentityModel>>(e, st).copyWithPrevious(previousState);
      // Rethrow so the caller (e.g. the identity form) can tell the user the
      // save failed instead of closing as if it had succeeded.
      rethrow;
    }
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
    final previousState = state;
    state = AsyncLoading<List<IdentityModel>>().copyWithPrevious(previousState);
    try {
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
      final items = await repo.getAllIdentities(decryptSecrets: false);
      state = AsyncData(items);
    } catch (e, st) {
      state = AsyncError<List<IdentityModel>>(e, st).copyWithPrevious(previousState);
      // Rethrow so the caller (e.g. the identity form) can tell the user the
      // save failed instead of closing as if it had succeeded.
      rethrow;
    }
  }

  Future<void> deleteIdentity(String id) async {
    final previousState = state;
    state = AsyncLoading<List<IdentityModel>>().copyWithPrevious(previousState);
    try {
      final repo = ref.read(vaultRepositoryProvider);
      await repo.deleteIdentity(id);
      final items = await repo.getAllIdentities(decryptSecrets: false);
      state = AsyncData(items);
    } catch (e, st) {
      state = AsyncError<List<IdentityModel>>(e, st).copyWithPrevious(previousState);
      // Rethrow so the caller (e.g. the identity form) can tell the user the
      // save failed instead of closing as if it had succeeded.
      rethrow;
    }
  }

  Future<IdentityModel?> getDecryptedIdentity(String id) async {
    final repo = ref.read(vaultRepositoryProvider);
    return await repo.getIdentityById(id, decryptSecrets: true);
  }
}
