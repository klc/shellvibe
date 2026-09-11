import '../../../../core/crypto/encryption_engine.dart';
import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/paired_devices_dao.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../vault/presentation/notifiers/vault_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef VaultUnlockedWrite =
    Future<T> Function<T>(Future<T> Function() operation);

/// Database boundary for desktop-side Device Link authorization records.
///
/// SQLite receives only the Argon2id record. The raw pairing secret is passed
/// through this class once, hashed, and discarded by the caller afterwards.
final class DeviceLinkPairingRepository {
  final PairedDevicesDao dao;
  final EncryptionEngine encryption;
  final bool Function() isVaultLocked;
  final VaultUnlockedWrite runWhileVaultUnlocked;

  const DeviceLinkPairingRepository({
    required this.dao,
    required this.encryption,
    required this.isVaultLocked,
    required this.runWhileVaultUnlocked,
  });

  Future<List<PairedDevice>> getAll() => dao.getAll();

  Stream<List<PairedDevice>> watchAll() => dao.watchAll();

  Future<void> savePairedDevice({
    required String id,
    required String name,
    required String platform,
    required String secret,
    required String publicKey,
    DateTime? pairedAt,
  }) async {
    // The hash operation is asynchronous. Check both sides of it so a vault
    // transition cannot leave a new authorization record behind.
    if (isVaultLocked()) {
      throw StateError(
        'Cannot save a Device Link pairing while vault is locked',
      );
    }
    final now = DateTime.now().toUtc();
    final hash = await encryption.hashSecret(secret);
    if (isVaultLocked()) {
      throw StateError(
        'Cannot save a Device Link pairing while vault is locked',
      );
    }
    await runWhileVaultUnlocked(
      () => dao.upsert(
        PairedDevicesCompanion.insert(
          id: id,
          name: name,
          platform: platform,
          secretHash: hash,
          publicKey: publicKey,
          pairedAt: (pairedAt ?? now).toUtc(),
          lastSeenAt: now,
        ),
      ),
    );
  }

  Future<bool> authenticate(String id, String secret) async {
    // Device Link is a local-PTY capability. A valid paired secret must not
    // bypass the vault lock while the desktop is waiting for an unlock.
    if (isVaultLocked()) return false;

    final device = await dao.findById(id);
    if (device == null) return false;
    final valid = await encryption.verifySecret(
      secret: secret,
      encodedHash: device.secretHash,
    );
    // Argon2id verification is asynchronous. A lock requested while it runs
    // must not turn a previously valid secret into a newly admitted session.
    if (!valid || isVaultLocked()) return false;
    try {
      await runWhileVaultUnlocked(
        () => dao.updateLastSeen(id, DateTime.now().toUtc()),
      );
    } on Object {
      // A lock closes the permit gate by throwing StateError. Do not mask an
      // unrelated database failure as an authentication failure.
      if (isVaultLocked()) return false;
      rethrow;
    }
    return !isVaultLocked();
  }

  Future<void> remove(String id) async {
    await dao.deleteById(id);
  }
}

final deviceLinkPairingRepositoryProvider =
    Provider<DeviceLinkPairingRepository>(
      (ref) => DeviceLinkPairingRepository(
        dao: ref.watch(pairedDevicesDaoProvider),
        encryption: ref.watch(encryptionEngineProvider),
        isVaultLocked: () {
          final vault = ref.read(vaultProvider);
          return vault.isLoading ||
              vault.hasError ||
              !vault.hasValue ||
              !vault.value!.allowsDeviceLink;
        },
        runWhileVaultUnlocked: ref
            .read(vaultProvider.notifier)
            .runWhileUnlocked,
      ),
    );

final pairedDevicesProvider = FutureProvider<List<PairedDevice>>((ref) {
  return ref.watch(deviceLinkPairingRepositoryProvider).getAll();
});
