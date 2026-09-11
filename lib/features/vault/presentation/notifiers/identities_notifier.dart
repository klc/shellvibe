import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../../../shared/providers/workspace_provider.dart';
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
VaultKeyService vaultKeyService(Ref ref) {
  return VaultKeyService(
    encryptionEngine: ref.watch(encryptionEngineProvider),
    secureStorageService: ref.watch(secureStorageServiceProvider),
  );
}

/// E2EE backup service. Needs the vault key to make backups self-contained.
@riverpod
E2EECloudSyncService e2eeCloudSyncService(Ref ref) {
  return E2EECloudSyncService(
    vaultKeyService: ref.watch(vaultKeyServiceProvider),
    cryptoEngine: ref.watch(encryptionEngineProvider),
  );
}

@riverpod
VaultRepository vaultRepository(Ref ref) {
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
    return await repo.getAllIdentities(
      decryptSecrets: false,
      workspaceId: ref.watch(activeWorkspaceIdProvider),
    );
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
      final items = await repo.getAllIdentities(
        decryptSecrets: false,
        workspaceId: ref.read(activeWorkspaceIdProvider),
      );
      state = AsyncData(items);
    } catch (_) {
      state = previousState;
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
      final items = await repo.getAllIdentities(
        decryptSecrets: false,
        workspaceId: ref.read(activeWorkspaceIdProvider),
      );
      state = AsyncData(items);
    } catch (_) {
      state = previousState;
      // Rethrow so the caller (e.g. the identity form) can tell the user the
      // save failed instead of closing as if it had succeeded.
      rethrow;
    }
  }

  Future<void> deleteIdentity(String id) async {
    final previousState = state;
    try {
      final repo = ref.read(vaultRepositoryProvider);
      await repo.deleteIdentity(id);
      final items = await repo.getAllIdentities(
        decryptSecrets: false,
        workspaceId: ref.read(activeWorkspaceIdProvider),
      );
      state = AsyncData(items);
    } catch (_) {
      state = previousState;
      // Rethrow so the caller (e.g. the identity form) can tell the user the
      // save failed instead of closing as if it had succeeded.
      rethrow;
    }
  }

  /// Ids of identities in the active workspace whose secrets cannot be
  /// decrypted, so the list can flag them instead of letting a broken identity
  /// look healthy until a connection fails.
  Future<Set<String>> findUndecryptableIds() async {
    final repo = ref.read(vaultRepositoryProvider);
    return repo.findUndecryptableIdentityIds(
      workspaceId: ref.read(activeWorkspaceIdProvider),
    );
  }

  Future<IdentityModel?> getDecryptedIdentity(String id) async {
    final repo = ref.read(vaultRepositoryProvider);
    return await repo.getIdentityById(id, decryptSecrets: true);
  }
}

/// Identities that need repairing, recomputed whenever the identity list or the
/// vault's lock state changes.
///
/// Kept out of [IdentitiesNotifier.build] on purpose: listing identities must
/// stay possible while the vault is locked, and must not decrypt secrets as a
/// side effect of drawing a list.
@riverpod
Future<Set<String>> undecryptableIdentityIds(Ref ref) async {
  final identities = await ref.watch(identitiesProvider.future);
  if (identities.isEmpty) return const {};
  return ref.read(identitiesProvider.notifier).findUndecryptableIds();
}
