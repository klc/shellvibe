import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

import '../../features/vault/data/vault_key_service.dart';
import '../../shared/database/app_database.dart';
import '../crypto/encryption_engine.dart';
import 'backup_envelope.dart';
import 'backup_scope.dart';

export 'backup_envelope.dart'
    show
        BackupEnvelope,
        BackupEnvelopeException,
        BackupUnlockMethod,
        kBackupSchemaVersion;
export 'backup_scope.dart';

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

  /// What the backup carried. A backup written before scopes existed reports
  /// [BackupScope.full], which is what it was.
  final BackupScope included;

  /// References that could not be resolved and what was done about them.
  final BackupRepairReport repairs;

  /// App settings from the backup, or null when it carried none.
  ///
  /// Returned rather than applied: this service owns the database, and the
  /// settings blob lives in secure storage behind a repository it does not
  /// know about.
  final Map<String, dynamic>? settings;

  const BackupImportResult({
    required this.secretsRecovered,
    this.warning,
    this.unlockedWith = BackupUnlockMethod.passphrase,
    this.schemaVersion = kBackupSchemaVersion,
    this.included = BackupScope.full,
    this.repairs = const BackupRepairReport(),
    this.settings,
  });
}

/// What a restore had to repair to fit the rows it was given.
///
/// Every number here is a thing the user should be told: a host restored
/// without its credentials still looks restored, and silence about that is how
/// "the sync broke my keys" reports start.
class BackupRepairReport {
  /// Hosts written with `identity_id` cleared, because the identity was not in
  /// the backup and is not on this device.
  final int hostsWithoutIdentity;

  /// Hosts whose jump host never arrived.
  final int hostsWithoutJumpHost;

  /// Host groups whose parent never arrived.
  final int groupsWithoutParent;

  /// Port forward rules dropped: `host_id` is NOT NULL.
  final int skippedPortForwards;

  /// Runbook steps dropped because their runbook is missing.
  final int skippedRunbookSteps;

  /// Template panes dropped because their template is missing.
  final int skippedTemplatePanes;

  /// Bookmarks dropped because neither their host nor their template exists.
  final int skippedBookmarks;

  /// Rows dropped because the workspace they belong to is missing.
  final int skippedForMissingWorkspace;

  const BackupRepairReport({
    this.hostsWithoutIdentity = 0,
    this.hostsWithoutJumpHost = 0,
    this.groupsWithoutParent = 0,
    this.skippedPortForwards = 0,
    this.skippedRunbookSteps = 0,
    this.skippedTemplatePanes = 0,
    this.skippedBookmarks = 0,
    this.skippedForMissingWorkspace = 0,
  });

  bool get isEmpty =>
      hostsWithoutIdentity == 0 &&
      hostsWithoutJumpHost == 0 &&
      groupsWithoutParent == 0 &&
      skippedPortForwards == 0 &&
      skippedRunbookSteps == 0 &&
      skippedTemplatePanes == 0 &&
      skippedBookmarks == 0 &&
      skippedForMissingWorkspace == 0;

  bool get isNotEmpty => !isEmpty;

  /// One sentence per repair, for the restore summary.
  List<String> get messages => [
    if (hostsWithoutIdentity > 0)
      '$hostsWithoutIdentity host restored without credentials, because the '
          'backup did not include identities.',
    if (hostsWithoutJumpHost > 0)
      '$hostsWithoutJumpHost host restored without its jump host.',
    if (groupsWithoutParent > 0)
      '$groupsWithoutParent group restored at the top level, because its '
          'parent group is missing.',
    if (skippedPortForwards > 0)
      '$skippedPortForwards port forward skipped: its host is not here.',
    if (skippedRunbookSteps > 0)
      '$skippedRunbookSteps runbook step skipped: its runbook is not here.',
    if (skippedTemplatePanes > 0)
      '$skippedTemplatePanes template pane skipped: its template is not here.',
    if (skippedBookmarks > 0)
      '$skippedBookmarks bookmark skipped: neither its host nor its layout is '
          'here.',
    if (skippedForMissingWorkspace > 0)
      '$skippedForMissingWorkspace row skipped: its workspace is not here.',
  ];
}

/// Mutable tally used while a restore runs.
class _RepairCounters {
  int hostsWithoutIdentity = 0;
  int hostsWithoutJumpHost = 0;
  int groupsWithoutParent = 0;
  int skippedPortForwards = 0;
  int skippedRunbookSteps = 0;
  int skippedTemplatePanes = 0;
  int skippedBookmarks = 0;
  int skippedForMissingWorkspace = 0;

  BackupRepairReport toReport() => BackupRepairReport(
    hostsWithoutIdentity: hostsWithoutIdentity,
    hostsWithoutJumpHost: hostsWithoutJumpHost,
    groupsWithoutParent: groupsWithoutParent,
    skippedPortForwards: skippedPortForwards,
    skippedRunbookSteps: skippedRunbookSteps,
    skippedTemplatePanes: skippedTemplatePanes,
    skippedBookmarks: skippedBookmarks,
    skippedForMissingWorkspace: skippedForMissingWorkspace,
  );
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
  ///
  /// [scope] selects what goes in. Workspaces and host groups are always
  /// written: everything else references them.
  ///
  /// [settings] is the app settings blob, which lives in secure storage rather
  /// than the database. It is passed in rather than read here so this service
  /// keeps its single dependency on [AppDatabase]; it is ignored unless
  /// [scope] includes [BackupCategory.settings].
  Future<String> exportEncryptedBackup({
    required AppDatabase db,
    required String masterPassword,
    String? recoveryCode,
    BackupScope scope = BackupScope.full,
    Map<String, dynamic>? settings,
  }) async {
    final workspaces = await db.select(db.workspaces).get();
    final hostGroups = await db.select(db.hostGroups).get();

    final payloadMap = <String, dynamic>{
      // 2 was the last version without a scope. A reader that sees 3 knows to
      // trust `included`; one that does not will treat an absent collection
      // the way it always has, as nothing to restore.
      'version': 3,
      'included': scope.toManifest(),
      'exported_at': DateTime.now().toIso8601String(),
      'workspaces': workspaces
          .map(
            (w) => {
              'id': w.id,
              'name': w.name,
              'colorCode': w.colorCode,
              'createdAt': w.createdAt.toIso8601String(),
            },
          )
          .toList(),
      'host_groups': hostGroups
          .map(
            (g) => {
              'id': g.id,
              'workspaceId': g.workspaceId,
              'parentId': g.parentId,
              'name': g.name,
              'colorTag': g.colorTag,
            },
          )
          .toList(),
    };

    if (scope.contains(BackupCategory.identities)) {
      final identities = await db.select(db.identities).get();
      payloadMap['identities'] = identities
          .map(
            (i) => {
              'id': i.id,
              'workspaceId': i.workspaceId,
              'title': i.title,
              'username': i.username,
              'authType': i.authType,
              'passwordEncrypted': i.passwordEncrypted,
              'privateKeyEncrypted': i.privateKeyEncrypted,
              'passphraseEncrypted': i.passphraseEncrypted,
              'createdAt': i.createdAt.toIso8601String(),
            },
          )
          .toList();
    }

    if (scope.contains(BackupCategory.hosts)) {
      final hosts = await db.select(db.hosts).get();
      // Every column on the table, not a subset. `username` was missing here
      // and a restored host tried to authenticate as whoever the client fell
      // back to, which reads to the user as the key being broken rather than
      // the backup being incomplete. `HostsBackupColumnsTest` fails if a new
      // column is added without being added here too.
      payloadMap['hosts'] = hosts
          .map(
            (h) => {
              'id': h.id,
              'workspaceId': h.workspaceId,
              'groupId': h.groupId,
              'identityId': h.identityId,
              'label': h.label,
              'hostname': h.hostname,
              'username': h.username,
              'port': h.port,
              'protocol': h.protocol,
              'moshServerPath': h.moshServerPath,
              'moshPortRange': h.moshPortRange,
              'colorTag': h.colorTag,
              'jumpHostId': h.jumpHostId,
              'environment': h.environment,
              'mcpVisible': h.mcpVisible,
              'mcpDefaultMode': h.mcpDefaultMode,
              'createdAt': h.createdAt.toIso8601String(),
            },
          )
          .toList();
    }

    if (scope.contains(BackupCategory.knownHosts)) {
      final knownHosts = await db.select(db.knownHosts).get();
      payloadMap['known_hosts'] = knownHosts
          .map(
            (k) => {
              'id': k.id,
              'hostname': k.hostname,
              'port': k.port,
              'keyType': k.keyType,
              'fingerprintSha256': k.fingerprintSha256,
              'firstSeenAt': k.firstSeenAt.toIso8601String(),
            },
          )
          .toList();
    }

    if (scope.contains(BackupCategory.portForwards)) {
      final portForwardRules = await db.select(db.portForwardRules).get();
      payloadMap['port_forward_rules'] = portForwardRules
          .map(
            (p) => {
              'id': p.id,
              'hostId': p.hostId,
              'type': p.type,
              'localPort': p.localPort,
              'remoteHost': p.remoteHost,
              'remotePort': p.remotePort,
              'autoStart': p.autoStart,
            },
          )
          .toList();
    }

    if (scope.contains(BackupCategory.snippetsAndRunbooks)) {
      final snippets = await db.select(db.snippets).get();
      final runbooks = await db.select(db.runbooks).get();
      final runbookSteps = await db.select(db.runbookSteps).get();

      payloadMap['snippets'] = snippets
          .map(
            (s) => {
              'id': s.id,
              'workspaceId': s.workspaceId,
              'title': s.title,
              'code': s.code,
              'tags': s.tags,
            },
          )
          .toList();
      payloadMap['runbooks'] = runbooks
          .map(
            (r) => {
              'id': r.id,
              'workspaceId': r.workspaceId,
              'title': r.title,
              'description': r.description,
              'createdAt': r.createdAt.toIso8601String(),
            },
          )
          .toList();
      payloadMap['runbook_steps'] = runbookSteps
          .map(
            (rs) => {
              'id': rs.id,
              'runbookId': rs.runbookId,
              'stepOrder': rs.stepOrder,
              'command': rs.command,
              'expectedExitCode': rs.expectedExitCode,
              'expectedOutputPattern': rs.expectedOutputPattern,
              'timeoutSeconds': rs.timeoutSeconds,
            },
          )
          .toList();
    }

    if (scope.contains(BackupCategory.templates)) {
      final templates = await db.select(db.templates).get();
      final templatePanes = await db.select(db.templatePanes).get();

      payloadMap['templates'] = templates
          .map(
            (t) => {
              'id': t.id,
              'workspaceId': t.workspaceId,
              'name': t.name,
              'description': t.description,
              'activePaneId': t.activePaneId,
              'createdAt': t.createdAt.toIso8601String(),
            },
          )
          .toList();
      payloadMap['template_panes'] = templatePanes
          .map(
            (tp) => {
              'id': tp.id,
              'templateId': tp.templateId,
              'paneOrder': tp.paneOrder,
              'parentPaneId': tp.parentPaneId,
              'splitDirection': tp.splitDirection,
              'splitRatio': tp.splitRatio,
              'sessionType': tp.sessionType,
              'hostId': tp.hostId,
              'title': tp.title,
            },
          )
          .toList();
    }

    if (scope.contains(BackupCategory.bookmarks)) {
      final bookmarks = await db.select(db.bookmarks).get();
      payloadMap['bookmarks'] = bookmarks
          .map(
            (b) => {
              'id': b.id,
              'workspaceId': b.workspaceId,
              'hostId': b.hostId,
              'templateId': b.templateId,
              'position': b.position,
              'createdAt': b.createdAt.toIso8601String(),
            },
          )
          .toList();
    }

    if (scope.contains(BackupCategory.settings) && settings != null) {
      payloadMap['settings'] = settings;
    }

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
  ///
  /// Nothing is ever deleted: every collection is upserted, so a backup that
  /// was taken with a narrowed scope leaves the categories it omits exactly as
  /// they are on this device.
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
    final included = BackupScope.fromManifest(data['included']);

    // Resolve both keys up front -- a locked vault must abort before the
    // transaction opens, not halfway through the restore.
    final backupDek = opened.backupDek;
    final localDek = backupDek == null ? null : await vaultKeyService.getDek();

    final repairs = _RepairCounters();

    await db.transaction(() async {
      // Two tables in this payload reference themselves: `hosts.jump_host_id`
      // points at another host, and `host_groups.parent_id` at another group.
      // The rows are restored in whatever order the backup lists them, so a
      // host whose jump host comes later in the list failed its foreign key at
      // the moment it was inserted -- and took the whole restore down with it.
      //
      // Deferring moves every check to COMMIT, by which point all the rows
      // exist. It is also the only ordering-independent answer: topologically
      // sorting two tables today would leave the next self-reference to
      // rediscover this the same way, on someone's phone.
      await db.customStatement('PRAGMA defer_foreign_keys = ON;');

      // Which ids exist once a level has been written. Read from the database
      // rather than from the payload: a partial backup may reference a row
      // this device already has, and that reference is perfectly good.
      Future<Set<String>> idsOf(String table) async {
        final rows = await db.customSelect('SELECT id FROM $table').get();
        return rows.map((r) => r.read<String>('id')).toSet();
      }

      // 1. Workspaces
      if (data['workspaces'] is List) {
        for (final item in data['workspaces'] as List) {
          await db
              .into(db.workspaces)
              .insertOnConflictUpdate(
                WorkspacesCompanion.insert(
                  id: item['id'] as String,
                  name: item['name'] as String,
                  colorCode: Value(item['colorCode'] as String?),
                  createdAt: DateTime.parse(item['createdAt'] as String),
                ),
              );
        }
      }
      final workspaceIds = await idsOf('workspaces');

      // 2. Identities
      if (data['identities'] is List) {
        for (final item in data['identities'] as List) {
          if (!workspaceIds.contains(item['workspaceId'])) {
            repairs.skippedForMissingWorkspace++;
            continue;
          }
          await db
              .into(db.identities)
              .insertOnConflictUpdate(
                IdentitiesCompanion.insert(
                  id: item['id'] as String,
                  workspaceId: item['workspaceId'] as String,
                  title: item['title'] as String,
                  username: item['username'] as String,
                  // A backup written by a build that still offered the removed
                  // SSH agent option would otherwise reintroduce rows the
                  // v7 migration just rewrote.
                  authType: _normalizeAuthType(item['authType'] as String),
                  passwordEncrypted: Value(
                    await _rewrapSecret(
                      item['passwordEncrypted'] as String?,
                      backupDek,
                      localDek,
                    ),
                  ),
                  privateKeyEncrypted: Value(
                    await _rewrapSecret(
                      item['privateKeyEncrypted'] as String?,
                      backupDek,
                      localDek,
                    ),
                  ),
                  passphraseEncrypted: Value(
                    await _rewrapSecret(
                      item['passphraseEncrypted'] as String?,
                      backupDek,
                      localDek,
                    ),
                  ),
                  createdAt: DateTime.parse(item['createdAt'] as String),
                ),
              );
        }
      }
      final identityIds = await idsOf('identities');

      // 3. Host Groups
      if (data['host_groups'] is List) {
        for (final item in data['host_groups'] as List) {
          if (!workspaceIds.contains(item['workspaceId'])) {
            repairs.skippedForMissingWorkspace++;
            continue;
          }
          await db
              .into(db.hostGroups)
              .insertOnConflictUpdate(
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
      final groupIds = await idsOf('host_groups');

      // 4. Hosts
      //
      // `identity_id` and `group_id` are nullable with `ON DELETE SET NULL`,
      // so a host whose identity was left out of the backup is written without
      // one rather than dropped. The schema already sanctions that state; a
      // host that cannot be reached is still better than a restore that stops.
      if (data['hosts'] is List) {
        for (final item in data['hosts'] as List) {
          if (!workspaceIds.contains(item['workspaceId'])) {
            repairs.skippedForMissingWorkspace++;
            continue;
          }

          final identityId = item['identityId'] as String?;
          final keepIdentity =
              identityId != null && identityIds.contains(identityId);
          if (identityId != null && !keepIdentity) {
            repairs.hostsWithoutIdentity++;
          }

          final groupId = item['groupId'] as String?;
          final keepGroup = groupId != null && groupIds.contains(groupId);

          await db
              .into(db.hosts)
              .insertOnConflictUpdate(
                HostsCompanion.insert(
                  id: item['id'] as String,
                  workspaceId: item['workspaceId'] as String,
                  groupId: Value(keepGroup ? groupId : null),
                  identityId: Value(keepIdentity ? identityId : null),
                  label: item['label'] as String,
                  hostname: item['hostname'] as String,
                  // Absent in backups written before these columns were
                  // exported; the table's own defaults apply then.
                  username: Value(item['username'] as String?),
                  port: Value(item['port'] as int? ?? 22),
                  protocol: Value(item['protocol'] as String? ?? 'ssh'),
                  moshServerPath: Value(item['moshServerPath'] as String?),
                  moshPortRange: Value(item['moshPortRange'] as String?),
                  colorTag: Value(item['colorTag'] as String?),
                  jumpHostId: Value(item['jumpHostId'] as String?),
                  environment: Value(item['environment'] as String? ?? 'dev'),
                  mcpVisible: Value(item['mcpVisible'] as bool? ?? true),
                  mcpDefaultMode: Value(
                    item['mcpDefaultMode'] as String? ?? 'readonly',
                  ),
                  createdAt: DateTime.parse(item['createdAt'] as String),
                ),
              );
        }
      }
      final hostIds = await idsOf('hosts');

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
                firstSeenAt: Value(
                  DateTime.parse(item['firstSeenAt'] as String),
                ),
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
      //
      // `host_id` is NOT NULL, so a rule whose host is missing is a row that
      // cannot exist. Skipping it is the only alternative to failing the whole
      // restore at COMMIT.
      if (data['port_forward_rules'] is List) {
        for (final item in data['port_forward_rules'] as List) {
          if (!hostIds.contains(item['hostId'])) {
            repairs.skippedPortForwards++;
            continue;
          }
          await db
              .into(db.portForwardRules)
              .insertOnConflictUpdate(
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
          if (!workspaceIds.contains(item['workspaceId'])) {
            repairs.skippedForMissingWorkspace++;
            continue;
          }
          await db
              .into(db.snippets)
              .insertOnConflictUpdate(
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
          if (!workspaceIds.contains(item['workspaceId'])) {
            repairs.skippedForMissingWorkspace++;
            continue;
          }
          await db
              .into(db.runbooks)
              .insertOnConflictUpdate(
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
      final runbookIds = await idsOf('runbooks');

      // 9. Runbook Steps
      if (data['runbook_steps'] is List) {
        for (final item in data['runbook_steps'] as List) {
          if (!runbookIds.contains(item['runbookId'])) {
            repairs.skippedRunbookSteps++;
            continue;
          }
          await db
              .into(db.runbookSteps)
              .insertOnConflictUpdate(
                RunbookStepsCompanion.insert(
                  id: item['id'] as String,
                  runbookId: item['runbookId'] as String,
                  stepOrder: item['stepOrder'] as int,
                  command: item['command'] as String,
                  expectedExitCode: Value(
                    item['expectedExitCode'] as int? ?? 0,
                  ),
                  expectedOutputPattern: Value(
                    item['expectedOutputPattern'] as String?,
                  ),
                  timeoutSeconds: Value(item['timeoutSeconds'] as int? ?? 30),
                ),
              );
        }
      }

      // 10. Templates
      if (data['templates'] is List) {
        for (final item in data['templates'] as List) {
          if (!workspaceIds.contains(item['workspaceId'])) {
            repairs.skippedForMissingWorkspace++;
            continue;
          }
          await db
              .into(db.templates)
              .insertOnConflictUpdate(
                TemplatesCompanion.insert(
                  id: item['id'] as String,
                  workspaceId: item['workspaceId'] as String,
                  name: item['name'] as String,
                  description: Value(item['description'] as String?),
                  activePaneId: Value(item['activePaneId'] as String?),
                  createdAt: DateTime.parse(item['createdAt'] as String),
                ),
              );
        }
      }
      final templateIds = await idsOf('templates');

      // 11. Template Panes
      //
      // `host_id` here is deliberately not a foreign key -- deleting a host
      // must not rewrite a saved layout -- so a pane whose host did not come
      // with the backup is written as it is and skipped with a warning when
      // the template runs. That is existing behaviour, not a new compromise.
      if (data['template_panes'] is List) {
        for (final item in data['template_panes'] as List) {
          if (!templateIds.contains(item['templateId'])) {
            repairs.skippedTemplatePanes++;
            continue;
          }
          await db
              .into(db.templatePanes)
              .insertOnConflictUpdate(
                TemplatePanesCompanion.insert(
                  id: item['id'] as String,
                  templateId: item['templateId'] as String,
                  paneOrder: item['paneOrder'] as int,
                  parentPaneId: Value(item['parentPaneId'] as String?),
                  splitDirection: Value(item['splitDirection'] as String?),
                  splitRatio: Value(
                    (item['splitRatio'] as num?)?.toDouble() ?? 0.5,
                  ),
                  sessionType: item['sessionType'] as String,
                  hostId: Value(item['hostId'] as String?),
                  title: Value(item['title'] as String?),
                ),
              );
        }
      }

      // 12. Bookmarks
      //
      // Both targets are nullable, so a bookmark survives a backup that left
      // its host or its template behind. One that loses *both* points at
      // nothing and is dropped instead of restored as a dead row.
      if (data['bookmarks'] is List) {
        for (final item in data['bookmarks'] as List) {
          if (!workspaceIds.contains(item['workspaceId'])) {
            repairs.skippedForMissingWorkspace++;
            continue;
          }

          final hostId = item['hostId'] as String?;
          final templateId = item['templateId'] as String?;
          final keepHost = hostId != null && hostIds.contains(hostId);
          final keepTemplate =
              templateId != null && templateIds.contains(templateId);

          if (!keepHost && !keepTemplate) {
            repairs.skippedBookmarks++;
            continue;
          }

          await db
              .into(db.bookmarks)
              .insertOnConflictUpdate(
                BookmarksCompanion.insert(
                  id: item['id'] as String,
                  workspaceId: item['workspaceId'] as String,
                  hostId: Value(keepHost ? hostId : null),
                  templateId: Value(keepTemplate ? templateId : null),
                  position: Value(item['position'] as int? ?? 0),
                  createdAt: DateTime.parse(item['createdAt'] as String),
                ),
              );
        }
      }

      // 13. Self-references, last.
      //
      // `hosts.jump_host_id` and `host_groups.parent_id` point inside their own
      // table, so they cannot be checked while the rows are still arriving.
      // Foreign key checks are deferred to COMMIT, which means one dangling
      // reference would fail the entire restore -- the 2026-09-18 bug class.
      // Clear the ones that never arrived, and count them.
      repairs.hostsWithoutJumpHost += await _clearDanglingSelfReference(
        db,
        table: 'hosts',
        column: 'jump_host_id',
      );
      repairs.groupsWithoutParent += await _clearDanglingSelfReference(
        db,
        table: 'host_groups',
        column: 'parent_id',
      );
    });

    final settings = included.contains(BackupCategory.settings)
        ? data['settings'] as Map<String, dynamic>?
        : null;

    if (backupDek == null) {
      return BackupImportResult(
        secretsRecovered: false,
        warning:
            'This is a legacy (v1) backup: it does not contain the vault '
            'key, so stored passwords and private keys cannot be decrypted on '
            'this device and must be re-entered.',
        unlockedWith: opened.unlockedWith,
        schemaVersion: opened.schemaVersion,
        included: included,
        repairs: repairs.toReport(),
        settings: settings,
      );
    }

    return BackupImportResult(
      secretsRecovered: true,
      unlockedWith: opened.unlockedWith,
      schemaVersion: opened.schemaVersion,
      included: included,
      repairs: repairs.toReport(),
      settings: settings,
    );
  }

  /// Nulls out [column] where it points at a row of [table] that does not
  /// exist, and returns how many rows were changed.
  Future<int> _clearDanglingSelfReference(
    AppDatabase db, {
    required String table,
    required String column,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM $table '
          'WHERE $column IS NOT NULL '
          'AND $column NOT IN (SELECT id FROM $table)',
        )
        .getSingle();

    final count = rows.read<int>('n');
    if (count == 0) return 0;

    await db.customStatement(
      'UPDATE $table SET $column = NULL '
      'WHERE $column IS NOT NULL '
      'AND $column NOT IN (SELECT id FROM $table)',
    );

    return count;
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
