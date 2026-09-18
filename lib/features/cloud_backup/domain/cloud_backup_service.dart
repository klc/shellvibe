import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/sync/e2ee_cloud_sync_service.dart';
import '../../../shared/database/app_database.dart';
import '../data/cloud_backup_api.dart';

/// Encryption scheme version sent alongside the envelope's own
/// `schema_version`.
///
/// Separate on purpose: the envelope version describes the *layout*, this one
/// the cipher and KDF choice. They move independently.
const int kEncryptionVersion = 2;

/// Why an upload could not be attempted or completed.
enum CloudBackupFailure {
  /// The plan does not include cloud backup, or the server refused the call.
  notEntitled,

  /// The envelope is larger than the plan allows.
  tooLarge,

  /// Another device uploaded since this one last read the head.
  conflict,

  /// Rate limited. Retry later.
  throttled,

  /// Network or server trouble.
  unavailable,

  /// The vault is locked, or the passphrase is wrong.
  cryptography,
}

/// Outcome of an upload attempt.
@immutable
final class CloudBackupUploadResult {
  final bool succeeded;

  /// Revision the server stored, when it succeeded.
  final int? revision;

  final CloudBackupFailure? failure;

  /// One sentence for the user.
  final String? message;

  /// The server's head when a conflict was detected, so the UI can offer
  /// "restore that first" against a real number.
  final int? serverRevision;

  const CloudBackupUploadResult.success({required this.revision})
    : succeeded = true,
      failure = null,
      message = null,
      serverRevision = null;

  const CloudBackupUploadResult.failed({
    required this.failure,
    required this.message,
    this.serverRevision,
  }) : succeeded = false,
       revision = null;
}

/// Drives encrypted backups between the local database and the server vault.
///
/// Owns the orchestration only. Sealing and opening envelopes stays in
/// [E2EECloudSyncService] and [BackupEnvelope]; carrying opaque strings stays
/// in [CloudBackupApi]. Nothing here ever sees a decrypted payload.
final class CloudBackupService {
  final CloudBackupApi api;
  final E2EECloudSyncService sync;

  /// Persists the pending upload id across a restart, so a retry after a
  /// crash reuses it instead of writing a second revision.
  final Future<String?> Function() readPendingUploadId;
  final Future<void> Function(String? uploadId) writePendingUploadId;

  /// Produces a fresh idempotency key. Injectable so a test can pin it.
  final String Function() newUploadId;

  const CloudBackupService({
    required this.api,
    required this.sync,
    required this.readPendingUploadId,
    required this.writePendingUploadId,
    required this.newUploadId,
  });

  /// Reads what the server currently holds.
  Future<VaultHead> head() => api.head();

  /// Lists stored revisions.
  Future<List<BackupRevision>> revisions() => api.revisions();

  /// Seals the database and uploads it as a new revision.
  ///
  /// [maxSizeBytes] comes from the entitlement snapshot. Checking it here
  /// spends no request to learn a limit the client already knows, and produces
  /// a sentence the user can act on rather than a `429` whose code also means
  /// "too many requests".
  ///
  /// [force] re-reads the head and uploads on top of it after a conflict. That
  /// overwrites what the other device stored, so it is only ever called from an
  /// explicit user choice -- never automatically.
  Future<CloudBackupUploadResult> upload({
    required AppDatabase db,
    required String passphrase,
    required String deviceId,
    required int maxSizeBytes,
    String? recoveryCode,
    bool force = false,
  }) async {
    final String envelope;
    try {
      envelope = await sync.exportEncryptedBackup(
        db: db,
        masterPassword: passphrase,
        recoveryCode: recoveryCode,
      );
    } on Object catch (e) {
      return CloudBackupUploadResult.failed(
        failure: CloudBackupFailure.cryptography,
        message: 'The backup could not be encrypted: $e',
      );
    }

    final bytes = utf8.encode(envelope);

    if (maxSizeBytes > 0 && bytes.length > maxSizeBytes) {
      // Base64 and JSON inflate the payload well past the raw data size, so
      // this trips on vaults that look comfortably under the limit.
      return CloudBackupUploadResult.failed(
        failure: CloudBackupFailure.tooLarge,
        message:
            'This backup is ${_megabytes(bytes.length)}, over the '
            '${_megabytes(maxSizeBytes)} your plan allows.',
      );
    }

    final digest = await Sha256().hash(bytes);
    final checksum = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    // Reserve the idempotency key before the request. A reply that never
    // arrives is indistinguishable from one that never left, and only a
    // persisted key lets the retry be recognised as the same write.
    final uploadId = await readPendingUploadId() ?? newUploadId();
    await writePendingUploadId(uploadId);

    try {
      final head = await api.head();

      final revision = await api.upload(
        baseRevision: head.currentRevision,
        uploadId: uploadId,
        deviceId: deviceId,
        schemaVersion: kBackupSchemaVersion,
        encryptionVersion: kEncryptionVersion,
        ciphertext: envelope,
        ciphertextSha256: checksum,
      );

      await writePendingUploadId(null);

      return CloudBackupUploadResult.success(revision: revision.revision);
    } on ApiException catch (e) {
      return _mapUploadFailure(
        e,
        retry: force
            ? () => upload(
                db: db,
                passphrase: passphrase,
                deviceId: deviceId,
                maxSizeBytes: maxSizeBytes,
                recoveryCode: recoveryCode,
              )
            : null,
      );
    } on ApiTransportException catch (e) {
      // The upload id stays reserved: this is exactly the case it exists for.
      return CloudBackupUploadResult.failed(
        failure: CloudBackupFailure.unavailable,
        message: e.timedOut
            ? 'The server did not answer in time. The backup will resume as the '
                  'same upload when you try again.'
            : 'The server could not be reached.',
      );
    }
  }

  /// Downloads [revision] and restores it into [db].
  ///
  /// Verifies the server's checksum against the bytes actually received before
  /// decrypting. A mismatch aborts without touching the database.
  Future<BackupImportResult> restore({
    required AppDatabase db,
    required int revision,
    required String secret,
    BackupUnlockMethod unlockWith = BackupUnlockMethod.passphrase,
  }) async {
    final stored = await api.revision(revision);
    final ciphertext = stored.ciphertext;

    if (ciphertext == null || ciphertext.isEmpty) {
      throw const BackupEnvelopeException(
        'The server returned a revision with no ciphertext.',
      );
    }

    final digest = await Sha256().hash(utf8.encode(ciphertext));
    final checksum = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    if (stored.ciphertextSha256.isNotEmpty &&
        checksum.toLowerCase() != stored.ciphertextSha256.toLowerCase()) {
      throw const BackupEnvelopeException(
        'The downloaded backup does not match its checksum. Nothing was '
        'restored.',
      );
    }

    return sync.importEncryptedBackup(
      backupPackageJson: ciphertext,
      db: db,
      masterPassword: secret,
      unlockWith: unlockWith,
    );
  }

  /// Deletes the vault and every revision. Irreversible.
  Future<void> deleteVault() async {
    await api.deleteVault();
    await writePendingUploadId(null);
  }

  Future<CloudBackupUploadResult> _mapUploadFailure(
    ApiException e, {
    Future<CloudBackupUploadResult> Function()? retry,
  }) async {
    if (e.isSyncConflict) {
      if (retry != null) {
        // A forced retry is a new write, not the same one: reusing the
        // reserved id would make the server hand back the losing revision.
        await writePendingUploadId(null);

        return retry();
      }

      return CloudBackupUploadResult.failed(
        failure: CloudBackupFailure.conflict,
        message:
            'Another device backed up after this one last checked. Restore '
            'that backup first, or overwrite it.',
        serverRevision: e.detailInt('current_revision'),
      );
    }

    if (e.isPlanSizeLimit) {
      return CloudBackupUploadResult.failed(
        failure: CloudBackupFailure.tooLarge,
        message:
            'The server refused the backup as too large for your plan '
            '(${_megabytes(e.detailInt('max_size_bytes') ?? 0)} allowed).',
      );
    }

    if (e.isThrottled) {
      final seconds = e.retryAfterSeconds;

      return CloudBackupUploadResult.failed(
        failure: CloudBackupFailure.throttled,
        message: seconds == null
            ? 'Too many backups in a short time. Try again shortly.'
            : 'Too many backups in a short time. Try again in $seconds '
                  'seconds.',
      );
    }

    if (e.statusCode == 403) {
      return const CloudBackupUploadResult.failed(
        failure: CloudBackupFailure.notEntitled,
        message: 'Your plan does not include cloud backup.',
      );
    }

    return CloudBackupUploadResult.failed(
      failure: CloudBackupFailure.unavailable,
      message:
          'The backup was refused (${e.code}).'
          '${e.requestId == null ? '' : ' Reference: ${e.requestId}.'}',
    );
  }

  static String _megabytes(int bytes) {
    final mb = bytes / (1024 * 1024);

    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }
}
