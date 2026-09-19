import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';

/// The vault head: what the server currently holds.
@immutable
final class VaultHead {
  /// Server ULID of the vault, or empty when one has never been created.
  final String id;

  /// Revision number of the newest stored backup. `0` means the vault is
  /// empty, and is the [BackupRevision.baseRevision] a first upload sends.
  final int currentRevision;

  /// SHA-256 of the newest revision's ciphertext, or null when empty.
  final String? currentHash;

  /// Size of the **newest revision**, not the total the account occupies.
  ///
  /// `SyncController::putVault` assigns this the size of the revision it just
  /// wrote rather than accumulating, so presenting it as "storage used" would
  /// be wrong.
  final int newestRevisionBytes;

  final DateTime? updatedAt;

  const VaultHead({
    required this.id,
    required this.currentRevision,
    this.currentHash,
    this.newestRevisionBytes = 0,
    this.updatedAt,
  });

  /// The head of an account that has never uploaded.
  static const VaultHead empty = VaultHead(id: '', currentRevision: 0);

  bool get isEmpty => currentRevision == 0;

  static VaultHead fromJson(Map<String, Object?> json) => VaultHead(
    id: json['id'] as String? ?? '',
    currentRevision: _int(json['current_revision']),
    currentHash: json['current_hash'] as String?,
    newestRevisionBytes: _int(json['bytes_used']),
    updatedAt: _dateTime(json['updated_at']),
  );

  static int _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v) ?? 0,
    _ => 0,
  };

  static DateTime? _dateTime(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

/// One stored revision's metadata. The ciphertext is present only on the
/// single-revision read.
@immutable
final class BackupRevision {
  final String id;
  final int revision;
  final int baseRevision;

  /// The device that uploaded it, as the server recorded it.
  final String deviceId;

  final int schemaVersion;
  final int encryptionVersion;
  final String ciphertextSha256;
  final int sizeBytes;
  final DateTime? createdAt;

  /// The sealed envelope, present on `GET /sync/vault/revisions/{n}` only.
  final String? ciphertext;

  const BackupRevision({
    required this.id,
    required this.revision,
    required this.baseRevision,
    required this.deviceId,
    required this.schemaVersion,
    required this.encryptionVersion,
    required this.ciphertextSha256,
    required this.sizeBytes,
    this.createdAt,
    this.ciphertext,
  });

  static BackupRevision fromJson(Map<String, Object?> json) => BackupRevision(
    id: json['id'] as String? ?? '',
    revision: VaultHead._int(json['revision']),
    baseRevision: VaultHead._int(json['base_revision']),
    deviceId: json['device_id'] as String? ?? '',
    schemaVersion: VaultHead._int(json['schema_version']),
    encryptionVersion: VaultHead._int(json['encryption_version']),
    ciphertextSha256: json['ciphertext_sha256'] as String? ?? '',
    sizeBytes: VaultHead._int(json['size_bytes']),
    createdAt: VaultHead._dateTime(json['created_at']),
    ciphertext: json['ciphertext'] as String?,
  );
}

/// Which of an account's two vaults a call means.
///
/// They were one, and one revision chain cannot serve both. A sync snapshot
/// has to be rewritten as the operation log moves on, which inside the plan's
/// backup window would push the user's own backups out of it within a couple
/// of months. Separate lifetimes too: deleting your backups must not stop sync
/// on the devices that are still running.
enum VaultKind {
  /// What the user asked to keep.
  backup('backup'),

  /// The ground a joining device starts from, and the home of the operation
  /// log. Always written with the full scope -- a partial one cannot be the
  /// ground anything starts from.
  sync('sync');

  const VaultKind(this.wireName);

  final String wireName;
}

/// The `/sync/vault` half of the v1 API.
///
/// Carries opaque ciphertext and nothing else. It never sees a passphrase, a
/// key or a decrypted payload -- that is the whole point of the boundary, and
/// the reason this class takes and returns strings.
final class CloudBackupApi {
  final ApiClient client;

  /// The vault every call on this instance addresses.
  ///
  /// Fixed at construction rather than passed per call: an instance that could
  /// be pointed at either vault would put the decision at every call site, and
  /// one call site forgetting it writes a backup into the sync slot.
  final VaultKind kind;

  const CloudBackupApi({required this.client, this.kind = VaultKind.backup});

  Map<String, String> get _kindQuery => {'kind': kind.wireName};

  /// Reads the vault head. The server creates an empty vault on first read.
  Future<VaultHead> head() async {
    final response = await client.get('/sync/vault', query: _kindQuery);

    return VaultHead.fromJson(response.dataMap);
  }

  /// Lists stored revisions, newest first as the server orders them. The
  /// server caps this at 20.
  Future<List<BackupRevision>> revisions() async {
    final response = await client.get(
      '/sync/vault/revisions',
      query: _kindQuery,
    );

    return response.dataList
        .map(BackupRevision.fromJson)
        .toList(growable: false);
  }

  /// Downloads one revision, ciphertext included.
  Future<BackupRevision> revision(int revision) async {
    final response = await client.get(
      '/sync/vault/revisions/$revision',
      query: _kindQuery,
    );

    return BackupRevision.fromJson(response.dataMap);
  }

  /// Uploads a sealed envelope as a new revision.
  ///
  /// [uploadId] is the idempotency key and must be persisted *before* the call
  /// so a retry can reuse it: the server answers a repeat with the revision it
  /// already stored instead of writing a second one. Without that, a dropped
  /// connection on a successful write produces a duplicate revision and eats
  /// one of the plan's kept revisions.
  ///
  /// Throws `ApiException` with `isSyncConflict` when [baseRevision] is no
  /// longer the head, and with `isPlanSizeLimit` when the envelope exceeds the
  /// plan's allowance.
  Future<BackupRevision> upload({
    required int baseRevision,
    required String uploadId,
    required String deviceId,
    required int schemaVersion,
    required int encryptionVersion,
    required String ciphertext,
    required String ciphertextSha256,
  }) async {
    final response = await client.put(
      '/sync/vault',
      body: {
        'kind': kind.wireName,
        'base_revision': baseRevision,
        'upload_id': uploadId,
        'device_id': deviceId,
        'schema_version': schemaVersion,
        'encryption_version': encryptionVersion,
        'ciphertext': ciphertext,
        'ciphertext_sha256': ciphertextSha256,
      },
    );

    return BackupRevision.fromJson(response.dataMap);
  }

  /// Deletes the vault and every revision in it. Irreversible.
  Future<void> deleteVault() =>
      client.delete('/sync/vault', body: {'kind': kind.wireName});
}
