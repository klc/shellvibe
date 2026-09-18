import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

import '../../features/vault/data/vault_key_service.dart';
import '../../shared/database/app_database.dart';
import '../crypto/encryption_engine.dart';
import 'backup_envelope.dart';

export 'backup_envelope.dart'
    show
        BackupEnvelope,
        BackupEnvelopeException,
        BackupUnlockMethod,
        kBackupSchemaVersion;

/// Outcome of [E2EECloudSyncService.importEncryptedBackup].
class BackupImportResult {
  /// True when identity secrets were re-encrypted under this device's vault key
  /// and are therefore usable. False for legacy v1 backups.
  final bool secretsRecovered;

  /// Human-readable warning to surface, or null when the import was complete.
  final String? warning;

  /// Which secret opened the envelope. Always
  /// [BackupUnlockMethod.passphrase] for a v1 or v2 backup, which has no
  /// recovery path.
  final BackupUnlockMethod unlockedWith;

  /// Envelope version that was read.
  final int schemaVersion;

  const BackupImportResult({
    required this.secretsRecovered,
    this.warning,
    this.unlockedWith = BackupUnlockMethod.passphrase,
    this.schemaVersion = kBackupSchemaVersion,
  });
}

/// Zero-Knowledge E2EE Cloud Sync Abstraction Service.
/// Exports and imports encrypted database payloads using AES-256-GCM and Argon2id KDF.
class E2EECloudSyncService {
  final EncryptionEngine _cryptoEngine;
  final BackupEnvelope _envelope;
  final VaultKeyService vaultKeyService;

  E2EECloudSyncService({
    required this.vaultKeyService,
    EncryptionEngine? cryptoEngine,
    BackupEnvelope? envelope,
  }) : _cryptoEngine = cryptoEngine ?? EncryptionEngine(),
       _envelope =
           envelope ??
           BackupEnvelope(crypto: cryptoEngine ?? EncryptionEngine());

  /// Exports an encrypted Zero-Knowledge backup package from [db] using [masterPassword].
  Future<String> exportEncryptedBackup({
    required AppDatabase db,
    required String masterPassword,
    String? recoveryCode,
  }) async {
    final workspaces = await db.select(db.workspaces).get();
    final identities = await db.select(db.identities).get();
    final hostGroups = await db.select(db.hostGroups).get();
    final hosts = await db.select(db.hosts).get();
    final knownHosts = await db.select(db.knownHosts).get();
    final portForwardRules = await db.select(db.portForwardRules).get();
    final snippets = await db.select(db.snippets).get();
    final runbooks = await db.select(db.runbooks).get();
    final runbookSteps = await db.select(db.runbookSteps).get();

    final payloadMap = {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'workspaces': workspaces
          .map((w) => {
                'id': w.id,
                'name': w.name,
                'colorCode': w.colorCode,
                'createdAt': w.createdAt.toIso8601String(),
              })
          .toList(),
      'identities': identities
          .map((i) => {
                'id': i.id,
                'workspaceId': i.workspaceId,
                'title': i.title,
                'username': i.username,
                'authType': i.authType,
                'passwordEncrypted': i.passwordEncrypted,
                'privateKeyEncrypted': i.privateKeyEncrypted,
                'passphraseEncrypted': i.passphraseEncrypted,
                'createdAt': i.createdAt.toIso8601String(),
              })
          .toList(),
      'host_groups': hostGroups
          .map((g) => {
                'id': g.id,
                'workspaceId': g.workspaceId,
                'parentId': g.parentId,
                'name': g.name,
                'colorTag': g.colorTag,
              })
          .toList(),
      'hosts': hosts
          .map((h) => {
                'id': h.id,
                'workspaceId': h.workspaceId,
                'groupId': h.groupId,
                'identityId': h.identityId,
                'label': h.label,
                'hostname': h.hostname,
                'port': h.port,
                'protocol': h.protocol,
                'colorTag': h.colorTag,
                'jumpHostId': h.jumpHostId,
                'createdAt': h.createdAt.toIso8601String(),
              })
          .toList(),
      'known_hosts': knownHosts
          .map((k) => {
                'id': k.id,
                'hostname': k.hostname,
                'port': k.port,
                'keyType': k.keyType,
                'fingerprintSha256': k.fingerprintSha256,
                'firstSeenAt': k.firstSeenAt.toIso8601String(),
              })
          .toList(),
      'port_forward_rules': portForwardRules
          .map((p) => {
                'id': p.id,
                'hostId': p.hostId,
                'type': p.type,
                'localPort': p.localPort,
                'remoteHost': p.remoteHost,
                'remotePort': p.remotePort,
                'autoStart': p.autoStart,
              })
          .toList(),
      'snippets': snippets
          .map((s) => {
                'id': s.id,
                'workspaceId': s.workspaceId,
                'title': s.title,
                'code': s.code,
                'tags': s.tags,
              })
          .toList(),
      'runbooks': runbooks
          .map((r) => {
                'id': r.id,
                'workspaceId': r.workspaceId,
                'title': r.title,
                'description': r.description,
                'createdAt': r.createdAt.toIso8601String(),
              })
          .toList(),
      'runbook_steps': runbookSteps
          .map((rs) => {
                'id': rs.id,
                'runbookId': rs.runbookId,
                'stepOrder': rs.stepOrder,
                'command': rs.command,
                'expectedExitCode': rs.expectedExitCode,
                'expectedOutputPattern': rs.expectedOutputPattern,
                'timeoutSeconds': rs.timeoutSeconds,
              })
          .toList(),
    };

    // Read the vault key first: if the vault is locked this must fail before
    // any payload is produced.
    final dek = await vaultKeyService.getDek();

    return _envelope.seal(
      payloadJson: jsonEncode(payloadMap),
      dek: dek,
      passphrase: masterPassword,
      recoveryCode: recoveryCode,
    );
  }

  /// Imports and restores an encrypted backup package into [db] using [masterPassword].
  ///
  /// For v2 envelopes the identity secrets are decrypted with the backup's own
  /// Data Encryption Key and re-encrypted under this device's vault key, so
  /// they stay usable after a cross-device restore. v1 envelopes carry no key;
  /// their secrets are restored as-is and flagged in [BackupImportResult].
  Future<BackupImportResult> importEncryptedBackup({
    required String backupPackageJson,
    required AppDatabase db,
    required String masterPassword,
    BackupUnlockMethod unlockWith = BackupUnlockMethod.passphrase,
  }) async {
    final opened = await _envelope.open(
      envelopeJson: backupPackageJson,
      secret: masterPassword,
      method: unlockWith,
    );

    final data = jsonDecode(opened.payloadJson) as Map<String, dynamic>;

    // Resolve both keys up front — a locked vault must abort before the
    // transaction opens, not halfway through the restore.
    final backupDek = opened.backupDek;
    final localDek = backupDek == null ? null : await vaultKeyService.getDek();

    await db.transaction(() async {
      // 1. Workspaces
      if (data['workspaces'] is List) {
        for (final item in data['workspaces'] as List) {
          await db.into(db.workspaces).insertOnConflictUpdate(
                WorkspacesCompanion.insert(
                  id: item['id'] as String,
                  name: item['name'] as String,
                  colorCode: Value(item['colorCode'] as String?),
                  createdAt: DateTime.parse(item['createdAt'] as String),
                ),
              );
        }
      }

      // 2. Identities
      if (data['identities'] is List) {
        for (final item in data['identities'] as List) {
          await db.into(db.identities).insertOnConflictUpdate(
                IdentitiesCompanion.insert(
                  id: item['id'] as String,
                  workspaceId: item['workspaceId'] as String,
                  title: item['title'] as String,
                  username: item['username'] as String,
                  // A backup written by a build that still offered the removed
                  // SSH agent option would otherwise reintroduce rows the
                  // v7 migration just rewrote.
                  authType: _normalizeAuthType(item['authType'] as String),
                  passwordEncrypted: Value(await _rewrapSecret(
                      item['passwordEncrypted'] as String?, backupDek, localDek)),
                  privateKeyEncrypted: Value(await _rewrapSecret(
                      item['privateKeyEncrypted'] as String?, backupDek, localDek)),
                  passphraseEncrypted: Value(await _rewrapSecret(
                      item['passphraseEncrypted'] as String?, backupDek, localDek)),
                  createdAt: DateTime.parse(item['createdAt'] as String),
                ),
              );
        }
      }

      // 3. Host Groups
      if (data['host_groups'] is List) {
        for (final item in data['host_groups'] as List) {
          await db.into(db.hostGroups).insertOnConflictUpdate(
                HostGroupsCompanion.insert(
                  id: item['id'] as String,
                  workspaceId: item['workspaceId'] as String,
                  parentId: Value(item['parentId'] as String?),
                  name: item['name'] as String,
                  colorTag: Value(item['colorTag'] as String?),
                ),
              );
        }
      }

      // 4. Hosts
      if (data['hosts'] is List) {
        for (final item in data['hosts'] as List) {
          await db.into(db.hosts).insertOnConflictUpdate(
                HostsCompanion.insert(
                  id: item['id'] as String,
                  workspaceId: item['workspaceId'] as String,
                  groupId: Value(item['groupId'] as String?),
                  identityId: Value(item['identityId'] as String?),
                  label: item['label'] as String,
                  hostname: item['hostname'] as String,
                  port: Value(item['port'] as int? ?? 22),
                  protocol: Value(item['protocol'] as String? ?? 'ssh'),
                  colorTag: Value(item['colorTag'] as String?),
                  jumpHostId: Value(item['jumpHostId'] as String?),
                  createdAt: DateTime.parse(item['createdAt'] as String),
                ),
              );
        }
      }

      // 5. Known Hosts
      //
      // `insertOnConflictUpdate` only upserts on the primary key (id), but
      // `(hostname, port)` is the actual unique constraint on this table. Two
      // devices that independently TOFU'd the same server end up with the
      // same (hostname, port) under different ids, so a plain id-keyed
      // upsert throws a UNIQUE constraint violation and rolls back the whole
      // restore. Look the row up by (hostname, port) first and update it in
      // place when it already exists.
      if (data['known_hosts'] is List) {
        for (final item in data['known_hosts'] as List) {
          final hostname = item['hostname'] as String;
          final port = item['port'] as int;
          final existing = await db.knownHostsDao.findKnownHost(hostname, port);
          if (existing != null) {
            await db.knownHostsDao.insertOrUpdateKnownHost(
              KnownHostsCompanion(
                id: Value(existing.id),
                hostname: Value(hostname),
                port: Value(port),
                keyType: Value(item['keyType'] as String),
                fingerprintSha256: Value(item['fingerprintSha256'] as String),
                firstSeenAt: Value(DateTime.parse(item['firstSeenAt'] as String)),
              ),
            );
          } else {
            await db.knownHostsDao.insertOrUpdateKnownHost(
              KnownHostsCompanion.insert(
                id: item['id'] as String,
                hostname: hostname,
                port: port,
                keyType: item['keyType'] as String,
                fingerprintSha256: item['fingerprintSha256'] as String,
                firstSeenAt: DateTime.parse(item['firstSeenAt'] as String),
              ),
            );
          }
        }
      }

      // 6. Port Forward Rules
      if (data['port_forward_rules'] is List) {
        for (final item in data['port_forward_rules'] as List) {
          await db.into(db.portForwardRules).insertOnConflictUpdate(
                PortForwardRulesCompanion.insert(
                  id: item['id'] as String,
                  hostId: item['hostId'] as String,
                  type: item['type'] as String,
                  localPort: item['localPort'] as int,
                  remoteHost: Value(item['remoteHost'] as String?),
                  remotePort: Value(item['remotePort'] as int?),
                  autoStart: Value(item['autoStart'] as bool? ?? false),
                ),
              );
        }
      }

      // 7. Snippets
      if (data['snippets'] is List) {
        for (final item in data['snippets'] as List) {
          await db.into(db.snippets).insertOnConflictUpdate(
                SnippetsCompanion.insert(
                  id: item['id'] as String,
                  workspaceId: item['workspaceId'] as String,
                  title: item['title'] as String,
                  code: item['code'] as String,
                  tags: Value(item['tags'] as String?),
                ),
              );
        }
      }

      // 8. Runbooks
      if (data['runbooks'] is List) {
        for (final item in data['runbooks'] as List) {
          await db.into(db.runbooks).insertOnConflictUpdate(
                RunbooksCompanion.insert(
                  id: item['id'] as String,
                  workspaceId: item['workspaceId'] as String,
                  title: item['title'] as String,
                  description: Value(item['description'] as String?),
                  createdAt: DateTime.parse(item['createdAt'] as String),
                ),
              );
        }
      }

      // 9. Runbook Steps
      if (data['runbook_steps'] is List) {
        for (final item in data['runbook_steps'] as List) {
          await db.into(db.runbookSteps).insertOnConflictUpdate(
                RunbookStepsCompanion.insert(
                  id: item['id'] as String,
                  runbookId: item['runbookId'] as String,
                  stepOrder: item['stepOrder'] as int,
                  command: item['command'] as String,
                  expectedExitCode: Value(item['expectedExitCode'] as int? ?? 0),
                  expectedOutputPattern: Value(item['expectedOutputPattern'] as String?),
                  timeoutSeconds: Value(item['timeoutSeconds'] as int? ?? 30),
                ),
              );
        }
      }
    });

    if (backupDek == null) {
      return BackupImportResult(
        secretsRecovered: false,
        warning:
            'This is a legacy (v1) backup: it does not contain the vault '
            'key, so stored passwords and private keys cannot be decrypted on '
            'this device and must be re-entered.',
        unlockedWith: opened.unlockedWith,
        schemaVersion: opened.schemaVersion,
      );
    }

    return BackupImportResult(
      secretsRecovered: true,
      unlockedWith: opened.unlockedWith,
      schemaVersion: opened.schemaVersion,
    );
  }

  /// Maps auth types this build no longer supports onto `'password'`.
  ///
  /// `'agent'` identities were never usable — no connection path read them —
  /// so an imported one is treated the same way the v7 schema migration
  /// treats a local leftover.
  String _normalizeAuthType(String authType) =>
      const {'password', 'key'}.contains(authType) ? authType : 'password';

  /// Re-encrypts one secret from the backup key to this device's vault key.
  ///
  /// Returns the ciphertext unchanged when the backup carries no key (v1).
  Future<String?> _rewrapSecret(
    String? ciphertext,
    SecretKey? backupDek,
    SecretKey? localDek,
  ) async {
    if (ciphertext == null) return null;
    if (backupDek == null || localDek == null) return ciphertext;

    final plaintext = await _cryptoEngine.decrypt(
      encryptedBase64: ciphertext,
      secretKey: backupDek,
    );
    return _cryptoEngine.encrypt(plaintext: plaintext, secretKey: localDek);
  }
}
