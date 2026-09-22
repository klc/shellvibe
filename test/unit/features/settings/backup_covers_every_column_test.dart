import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/core/sync/e2ee_cloud_sync_service.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// A backup has to carry every column, not the ones someone remembered.
///
/// `hosts.username` was missing. A restored host then authenticated as
/// whichever user the SSH client fell back to, which reads as "my key stopped
/// working" rather than "the backup was incomplete" -- the failure is far from
/// the cause, so it is the kind of gap that survives a long time.
///
/// Reported from a phone connecting to hosts it had restored from a desktop
/// backup.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase source;
  late AppDatabase target;
  late E2EECloudSyncService sync;

  const passphrase = 'column coverage passphrase';

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    source = AppDatabase(NativeDatabase.memory());
    target = AppDatabase(NativeDatabase.memory());

    final vaultKeyService = VaultKeyService(
      encryptionEngine: EncryptionEngine(),
      secureStorageService: SecureStorageService(),
    );
    await vaultKeyService.getDek();

    sync = E2EECloudSyncService(vaultKeyService: vaultKeyService);
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  test('every hosts column appears in the exported payload', () async {
    // The guard. A column added to the table and forgotten here fails this
    // test rather than quietly dropping out of everyone's backups.
    await source.into(source.hosts).insert(
      HostsCompanion.insert(
        id: 'h1',
        workspaceId: 'default',
        label: 'h',
        hostname: 'example.com',
        createdAt: DateTime.now(),
      ),
    );

    final envelope = await sync.exportEncryptedBackup(
      db: source,
      masterPassword: passphrase,
    );

    // Reach the payload the only way a client can: by opening the envelope.
    final opened = await BackupEnvelope().open(
      envelopeJson: envelope,
      secret: passphrase,
    );
    final payload = jsonDecode(opened.payloadJson) as Map<String, dynamic>;
    final exported = ((payload['hosts'] as List).first as Map)
        .keys
        .map((k) => k as String)
        .toSet();

    final columns = source.hosts.$columns.map((c) => c.name).toSet();

    // Drift names columns in snake_case; the payload uses the Dart names.
    String toSnake(String name) => name
        .replaceAllMapped(
          RegExp('[A-Z]'),
          (match) => '_${match.group(0)!.toLowerCase()}',
        );

    final exportedAsColumns = exported.map(toSnake).toSet();

    expect(
      columns.difference(exportedAsColumns),
      isEmpty,
      reason:
          'These hosts columns are not in the backup, so they are lost on '
          'every restore.',
    );
  });

  test('a host with its own username keeps it through a restore', () async {
    // The reported symptom, end to end: the host authenticated as the wrong
    // user because this field never left the source device.
    await source.into(source.hosts).insert(
      HostsCompanion.insert(
        id: 'h1',
        workspaceId: 'default',
        label: 'mia-master',
        hostname: '10.50.0.200',
        username: const Value('deploy'),
        port: const Value(22022),
        createdAt: DateTime.now(),
      ),
    );

    final envelope = await sync.exportEncryptedBackup(
      db: source,
      masterPassword: passphrase,
    );
    await sync.importEncryptedBackup(
      backupPackageJson: envelope,
      db: target,
      masterPassword: passphrase,
    );

    final restored = (await target.select(target.hosts).get()).single;

    expect(restored.username, 'deploy');
    expect(restored.port, 22022);
  });

  test('the other host settings survive too', () async {
    await source.into(source.hosts).insert(
      HostsCompanion.insert(
        id: 'h1',
        workspaceId: 'default',
        label: 'prod',
        hostname: 'prod.example.com',
        createdAt: DateTime.now(),
        protocol: const Value('mosh'),
        moshServerPath: const Value('/usr/local/bin/mosh-server'),
        moshPortRange: const Value('60000:60010'),
        environment: const Value('prod'),
        mcpVisible: const Value(false),
        mcpDefaultMode: const Value('guarded'),
      ),
    );

    final envelope = await sync.exportEncryptedBackup(
      db: source,
      masterPassword: passphrase,
    );
    await sync.importEncryptedBackup(
      backupPackageJson: envelope,
      db: target,
      masterPassword: passphrase,
    );

    final restored = (await target.select(target.hosts).get()).single;

    expect(restored.protocol, 'mosh');
    expect(restored.moshServerPath, '/usr/local/bin/mosh-server');
    expect(restored.moshPortRange, '60000:60010');
    expect(
      restored.environment,
      'prod',
      reason: 'The policy engine reads this; a host restored as dev is a '
          'safety signal silently downgraded.',
    );
    expect(restored.mcpVisible, isFalse);
    expect(restored.mcpDefaultMode, 'guarded');
  });

  test('a backup written before these fields still restores', () async {
    // Backwards compatibility: an older payload simply has no such keys, and
    // the table's own defaults have to apply rather than the restore failing.
    final legacyPayload = jsonEncode({
      'version': 1,
      'hosts': [
        {
          'id': 'h1',
          'workspaceId': 'default',
          'label': 'old',
          'hostname': 'old.example.com',
          'port': 22,
          'protocol': 'ssh',
          'createdAt': DateTime.now().toIso8601String(),
        },
      ],
    });

    final crypto = EncryptionEngine();
    final envelope = await BackupEnvelope(crypto: crypto).seal(
      payloadJson: legacyPayload,
      dek: await VaultKeyService(
        encryptionEngine: crypto,
        secureStorageService: SecureStorageService(),
      ).getDek(),
      passphrase: passphrase,
    );

    await sync.importEncryptedBackup(
      backupPackageJson: envelope,
      db: target,
      masterPassword: passphrase,
    );

    final restored = (await target.select(target.hosts).get()).single;

    expect(restored.username, isNull);
    expect(restored.environment, 'dev');
    expect(restored.mcpDefaultMode, 'readonly');
    expect(restored.mcpVisible, isTrue);
  });
}
