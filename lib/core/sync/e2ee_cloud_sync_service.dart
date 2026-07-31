import 'dart:convert';
import 'package:drift/drift.dart';

import '../../shared/database/app_database.dart';
import '../crypto/encryption_engine.dart';

/// Zero-Knowledge E2EE Cloud Sync Abstraction Service.
/// Exports and imports encrypted database payloads using AES-256-GCM and Argon2id KDF.
class E2EECloudSyncService {
  final EncryptionEngine _cryptoEngine;

  E2EECloudSyncService({EncryptionEngine? cryptoEngine})
      : _cryptoEngine = cryptoEngine ?? EncryptionEngine();

  /// Exports an encrypted Zero-Knowledge backup package from [db] using [masterPassword].
  Future<String> exportEncryptedBackup({
    required AppDatabase db,
    required String masterPassword,
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

    final jsonStr = jsonEncode(payloadMap);
    final salt = _cryptoEngine.generateSalt();
    final secretKey = await _cryptoEngine.deriveMasterKey(
      masterPassword: masterPassword,
      salt: salt,
    );

    final encryptedPayload = await _cryptoEngine.encrypt(
      plaintext: jsonStr,
      secretKey: secretKey,
    );

    final backupEnvelope = {
      'schema_version': 1,
      'salt': base64.encode(salt),
      'payload': encryptedPayload,
    };

    return jsonEncode(backupEnvelope);
  }

  /// Imports and restores an encrypted backup package into [db] using [masterPassword].
  Future<void> importEncryptedBackup({
    required String backupPackageJson,
    required AppDatabase db,
    required String masterPassword,
  }) async {
    final Map<String, dynamic> envelope = jsonDecode(backupPackageJson);
    final saltBase64 = envelope['salt'] as String;
    final payloadEncrypted = envelope['payload'] as String;

    final salt = Uint8List.fromList(base64.decode(saltBase64));
    final secretKey = await _cryptoEngine.deriveMasterKey(
      masterPassword: masterPassword,
      salt: salt,
    );

    final decryptedJsonStr = await _cryptoEngine.decrypt(
      encryptedBase64: payloadEncrypted,
      secretKey: secretKey,
    );

    final Map<String, dynamic> data = jsonDecode(decryptedJsonStr);

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
                  authType: item['authType'] as String,
                  passwordEncrypted: Value(item['passwordEncrypted'] as String?),
                  privateKeyEncrypted: Value(item['privateKeyEncrypted'] as String?),
                  passphraseEncrypted: Value(item['passphraseEncrypted'] as String?),
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
      if (data['known_hosts'] is List) {
        for (final item in data['known_hosts'] as List) {
          await db.into(db.knownHosts).insertOnConflictUpdate(
                KnownHostsCompanion.insert(
                  id: item['id'] as String,
                  hostname: item['hostname'] as String,
                  port: item['port'] as int,
                  keyType: item['keyType'] as String,
                  fingerprintSha256: item['fingerprintSha256'] as String,
                  firstSeenAt: DateTime.parse(item['firstSeenAt'] as String),
                ),
              );
        }
      }

      // 6. Snippets
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

      // 7. Runbooks
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

      // 8. Runbook Steps
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
  }
}
