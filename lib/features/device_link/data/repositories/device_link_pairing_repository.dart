import '../../../../core/crypto/encryption_engine.dart';
import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/paired_devices_dao.dart';
import '../../../../shared/providers/database_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Database boundary for desktop-side Device Link authorization records.
///
/// SQLite receives only the Argon2id record. The raw pairing secret is passed
/// through this class once, hashed, and discarded by the caller afterwards.
final class DeviceLinkPairingRepository {
  final PairedDevicesDao dao;
  final EncryptionEngine encryption;

  const DeviceLinkPairingRepository({
    required this.dao,
    required this.encryption,
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
    final now = DateTime.now().toUtc();
    final hash = await encryption.hashSecret(secret);
    await dao.upsert(
      PairedDevicesCompanion.insert(
        id: id,
        name: name,
        platform: platform,
        secretHash: hash,
        publicKey: publicKey,
        pairedAt: (pairedAt ?? now).toUtc(),
        lastSeenAt: now,
      ),
    );
  }

  Future<bool> authenticate(String id, String secret) async {
    final device = await dao.findById(id);
    if (device == null) return false;
    final valid = await encryption.verifySecret(
      secret: secret,
      encodedHash: device.secretHash,
    );
    if (valid) {
      await dao.updateLastSeen(id, DateTime.now().toUtc());
    }
    return valid;
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
      ),
    );

final pairedDevicesProvider = FutureProvider<List<PairedDevice>>((ref) {
  return ref.watch(deviceLinkPairingRepositoryProvider).getAll();
});
