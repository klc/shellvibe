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
  final VaultTransport api;
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
  /// [expectedRevision] is the revision this device last wrote or restored,
  /// sent as the base so the server refuses the write when another device has
  /// stored one since. Null bases the upload on whatever the server holds now,
  /// which is only right when this device's data already reflects that
  /// revision -- a converged sync, or a forced overwrite.
  ///
  /// [force] re-reads the head and uploads on top of it after a conflict. That
  /// overwrites what the other device stored, so it is only ever called from an
  /// explicit user choice -- never automatically.
  ///
  /// [scope] narrows what the backup carries. [settings] is the app settings
  /// blob, which lives in secure storage rather than the database and is
  /// therefore read by the caller.
  Future<CloudBackupUploadResult> upload({
    required AppDatabase db,
    required String passphrase,
    required String deviceId,
    required int maxSizeBytes,
    String? recoveryCode,
    int? expectedRevision,
    bool force = false,
    BackupScope scope = BackupScope.full,
    Map<String, dynamic>? settings,
    Uint8List? syncKey,
    int? syncClock,
  }) async {
    final String envelope;
    try {
      envelope = await sync.exportEncryptedBackup(
        db: db,
        masterPassword: passphrase,
        recoveryCode: recoveryCode,
        scope: scope,
        settings: settings,
        syncKey: syncKey,
        syncClock: syncClock,
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
    final pendingUploadId = await readPendingUploadId();
    final uploadId = pendingUploadId ?? newUploadId();
    await writePendingUploadId(uploadId);

    try {
      final head = await api.head();
      // An empty vault has nothing to conflict with: it was never written, or
      // it was deleted -- from another device or the web panel -- and the
      // revision this device remembers no longer exists anywhere.
      final base = force || head.isEmpty
          ? head.currentRevision
          : expectedRevision ?? head.currentRevision;

      // Read off the head rather than learned from a 409 after the upload: the
      // envelope is several megabytes, and the answer is already known. Not
      // for a resumed upload, though: the head may have moved because of that
      // very upload, whose reply never arrived, and only the server can match
      // it by its id and hand the stored revision back.
      if (pendingUploadId == null && base != head.currentRevision) {
        // Nothing was sent, so there is no write for the id to stand for.
        await writePendingUploadId(null);

        return CloudBackupUploadResult.failed(
          failure: CloudBackupFailure.conflict,
          message: _conflictMessage,
          serverRevision: head.currentRevision,
        );
      }

      final revision = await api.upload(
        baseRevision: base,
        uploadId: uploadId,
        deviceId: deviceId,
        // Read off the envelope, not assumed. A backup sealed without a sync
        // key is a v3 one, and announcing it as v4 marks a revision that an
        // older build can open as one it has to refuse.
        schemaVersion: BackupEnvelope.versionOf(envelope),
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
                // Everything the first attempt carried. Leaving these out
                // silently widened the scope the user chose and dropped the
                // sync key, which takes the envelope back to v3 -- and a v3
                // backup is one that no other device can start syncing from.
                scope: scope,
                settings: settings,
                syncKey: syncKey,
                syncClock: syncClock,
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
      // The device that wrote the revision, so the rows it restores break
      // clock ties the same way the operation that produced them would have.
      snapshotDeviceId: stored.deviceId,
    );
  }

  /// Checks that [secret] opens [revision], writing nothing.
  ///
  /// This is how a second device adopts an existing backup: it proves the
  /// passphrase before storing it, so a typo is caught at the point it is typed
  /// rather than at the next upload. Nothing touches the database -- the
  /// payload is decrypted and discarded, because the question here is only
  /// whether the key is right.
  Future<OpenedBackup?> canOpen({
    required int revision,
    required String secret,
    BackupUnlockMethod unlockWith = BackupUnlockMethod.passphrase,
  }) async {
    final stored = await api.revision(revision);
    final ciphertext = stored.ciphertext;

    if (ciphertext == null || ciphertext.isEmpty) return null;

    try {
      // The opened envelope is returned rather than discarded, because this is
      // also where a joining device learns the vault's sync key. It cannot be
      // derived or invented: every device has to hold the same one, and the
      // only place it exists is inside an envelope.
      return await BackupEnvelope().open(
        envelopeJson: ciphertext,
        secret: secret,
        method: unlockWith,
      );
    } on BackupEnvelopeException {
      return null;
    }
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
        message: _conflictMessage,
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

  static const String _conflictMessage =
      'Another device backed up after this one last checked. Restore that '
      'backup first, or overwrite it.';

  static String _megabytes(int bytes) {
    final mb = bytes / (1024 * 1024);

    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }
}
