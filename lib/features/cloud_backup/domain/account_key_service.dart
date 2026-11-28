import 'dart:typed_data';

import '../../../core/api/api_exception.dart';
import '../../../core/sync/account_key.dart';
import '../../../core/sync/backup_envelope.dart';
import '../data/account_key_api.dart';
import '../data/cloud_backup_store.dart';

/// How an attempt to give the account a key ended.
enum AccountKeyOutcome {
  /// This device now holds the account key.
  ready,

  /// The server does not hand out account keys yet, so this device carries on
  /// sealing with the passphrase. Nothing changed.
  notYet,

  /// The account has a key, and the secret this device has does not open it.
  /// The user has to say which one is right.
  wrongSecret,

  /// Another device set the account up between the check and the write. What
  /// it stored is the account's key now; this device unlocks it, it does not
  /// replace it.
  alreadyExists,
}

/// The life of the account key on one device: how it gets here, and what has
/// to be true before it is trusted.
///
/// One rule runs through all of it. **The record on the server is the
/// account's key, and a device only keeps a key that record vouches for.**
/// The record is written on top of a revision, so two devices that both try
/// to create it end with one -- the loser reads the winner's and adopts it.
/// Nothing here mints a key and carries on alone, which is how two devices
/// used to end up holding keys the other could not read.
final class AccountKeyService {
  final CloudBackupStore store;
  final AccountKeyTransport api;
  final AccountKeyRecord records;
  final String deviceId;

  AccountKeyService({
    required this.store,
    required this.api,
    required this.deviceId,
    AccountKeyRecord? records,
  }) : records = records ?? AccountKeyRecord();

  /// What the server holds, for a device deciding between setup and unlock.
  Future<AccountKeyHead> head() => api.read();

  /// The key this device seals with, and the record as the account has it
  /// now. Null on a device that holds no account key.
  ///
  /// The record is read here rather than remembered, so a recovery code added
  /// on another device is in the next backup this one writes instead of being
  /// quietly dropped by it.
  ///
  /// Throws [BackupEnvelopeException] when the account's record is not this
  /// key's: the account was set up again from somewhere else, and this device
  /// has to join it again.
  Future<AccountKey?> current() async {
    final key = await store.readAccountKey();
    if (key == null) return null;

    final record = (await api.read()).record;
    if (record == null || !await records.belongsTo(record, key)) {
      throw const BackupEnvelopeException(
        'The account key on this device no longer matches the account. '
        'Forget the setup on this device and add it again.',
      );
    }

    return AccountKey(bytes: key, record: record);
  }

  /// First-time setup: gives the account a key that [passphrase] and
  /// [recoveryCode] open.
  Future<AccountKeyOutcome> create({
    required String passphrase,
    required String recoveryCode,
  }) async {
    final head = await api.read();
    if (head.exists) return AccountKeyOutcome.alreadyExists;
    if (!head.enabled) return AccountKeyOutcome.notYet;

    final key = records.generateKey();

    try {
      await api.write(
        baseRevision: head.revision,
        record: await records.build(
          accountKey: key,
          passphrase: passphrase,
          recoveryCode: recoveryCode,
        ),
        deviceId: deviceId,
      );
    } on ApiException catch (e) {
      if (AccountKeyApi.isConflict(e)) return AccountKeyOutcome.alreadyExists;
      rethrow;
    }

    // After the server has it. A key stored first and never published is a
    // device sealing backups nothing else can open.
    await store.writeAccountKey(key);

    return AccountKeyOutcome.ready;
  }

  /// Joins with a typed [secret]: the passphrase, or the recovery code.
  ///
  /// Either one is enough now. The recovery code used to prove ownership and
  /// then stop, because a device needed the passphrase itself to seal with.
  Future<AccountKeyOutcome> unlock({
    required String secret,
    BackupUnlockMethod method = BackupUnlockMethod.passphrase,
  }) async {
    final record = (await api.read()).record;
    if (record == null) return AccountKeyOutcome.notYet;

    final Uint8List key;
    try {
      key = await records.open(
        recordJson: record,
        secret: secret,
        method: method,
      );
    } on BackupEnvelopeException {
      return AccountKeyOutcome.wrongSecret;
    }

    await store.writeAccountKey(key);

    return AccountKeyOutcome.ready;
  }

  /// Joins with a key another device handed over.
  ///
  /// Checked against the account's record before it is kept. The handoff
  /// already proves which device sent it; this proves that what it sent is
  /// this account's key and not, say, the key of an account that device used
  /// to be signed in to.
  Future<AccountKeyOutcome> adopt(Uint8List accountKey) async {
    final record = (await api.read()).record;
    if (record == null) return AccountKeyOutcome.notYet;
    if (!await records.belongsTo(record, accountKey)) {
      return AccountKeyOutcome.wrongSecret;
    }

    await store.writeAccountKey(accountKey);

    return AccountKeyOutcome.ready;
  }

  /// Moves a device that seals with the passphrase over to the account key.
  ///
  /// Safe to call on every start. The passphrase is left where it is: it is
  /// dropped separately, once nothing this device may have to read still
  /// needs it.
  Future<AccountKeyOutcome> migrate() async {
    if (await store.readAccountKey() != null) return AccountKeyOutcome.ready;

    final passphrase = await store.readPassphrase();
    if (passphrase == null) return AccountKeyOutcome.notYet;

    final recoveryCode = await store.readRecoveryCode();

    // Twice at most: the second time round is for the device that lost the
    // race to create the record and now has one to adopt.
    for (var attempt = 0; attempt < 2; attempt++) {
      final head = await api.read();

      if (head.exists) {
        final outcome = await unlock(secret: passphrase);
        if (outcome != AccountKeyOutcome.ready) return outcome;

        // The device that created the record may not have known the recovery
        // code. This one does, so it fills the gap.
        if (recoveryCode != null &&
            !AccountKeyRecord.hasRecoverySlot(head.record!)) {
          await _addRecoveryCode(head, recoveryCode);
        }

        return AccountKeyOutcome.ready;
      }

      if (!head.enabled) return AccountKeyOutcome.notYet;

      final key = records.generateKey();
      try {
        await api.write(
          baseRevision: head.revision,
          record: await records.build(
            accountKey: key,
            passphrase: passphrase,
            recoveryCode: recoveryCode,
          ),
          deviceId: deviceId,
        );
      } on ApiException catch (e) {
        if (AccountKeyApi.isConflict(e)) continue;
        rethrow;
      }

      await store.writeAccountKey(key);

      return AccountKeyOutcome.ready;
    }

    return AccountKeyOutcome.alreadyExists;
  }

  /// Gives the account [recoveryCode] as its recovery code, replacing any it
  /// had. Needs the key, not the passphrase.
  Future<void> setRecoveryCode(String recoveryCode) async {
    final head = await api.read();
    if (!head.exists) {
      throw const BackupEnvelopeException('This account has no key yet.');
    }

    await _addRecoveryCode(head, recoveryCode);
  }

  /// Whether the account can be recovered with a recovery code. True when
  /// there is no way to tell, so nobody is warned about a gap that may not be
  /// there.
  Future<bool> hasRecoveryCode() async {
    final record = (await api.read()).record;

    return record == null || AccountKeyRecord.hasRecoverySlot(record);
  }

  Future<void> _addRecoveryCode(
    AccountKeyHead head,
    String recoveryCode,
  ) async {
    final key = await store.readAccountKey();
    if (key == null) {
      throw const BackupEnvelopeException(
        'This device does not hold the account key.',
      );
    }

    try {
      await api.write(
        baseRevision: head.revision,
        record: await records.withRecoveryCode(
          recordJson: head.record!,
          accountKey: key,
          recoveryCode: recoveryCode,
        ),
        deviceId: deviceId,
      );
    } on ApiException catch (e) {
      // Another device changed the record first. Whatever it wrote stands;
      // the gap, if there still is one, is found again on the next start.
      if (!AccountKeyApi.isConflict(e)) rethrow;
    }
  }
}
