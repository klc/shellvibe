import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/core/sync/e2ee_cloud_sync_service.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// Restoring a backup that contains a jump host or a nested host group.
///
/// Reported from a phone restoring a desktop backup:
///
///     SqliteException(787): FOREIGN KEY constraint failed
///     INSERT INTO "hosts" (... "jump_host_id" ...)
///
/// `hosts.jump_host_id` references `hosts.id` and `host_groups.parent_id`
/// references `host_groups.id`. Rows are restored in the order the backup
/// lists them, so a host whose jump host happens to come later failed its
/// foreign key on insert and took the entire restore down.
///
/// Every earlier restore test used flat data, which is why this shipped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase source;
  late AppDatabase target;
  late E2EECloudSyncService sync;

  const passphrase = 'restore ordering passphrase';

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

  /// Builds a vault whose exported list puts each referencing row *before* the
  /// row it points at.
  ///
  /// The reference is set with an UPDATE after both rows exist, because the
  /// source database enforces the same foreign keys: the ordering problem only
  /// exists on the way back in, when the rows arrive one at a time.
  Future<void> seedSourceWithForwardReferences() async {
    const bastionId = 'aaaa-bastion';
    const behindId = 'bbbb-behind-the-bastion';

    // Inserted first, so it is exported first -- while pointing at a host that
    // is exported after it.
    await source.into(source.hosts).insert(
      HostsCompanion.insert(
        id: behindId,
        workspaceId: 'default',
        label: 'mia-master',
        hostname: '10.50.0.200',
        port: const Value(22022),
        createdAt: DateTime.now(),
      ),
    );

    await source.into(source.hosts).insert(
      HostsCompanion.insert(
        id: bastionId,
        workspaceId: 'default',
        label: 'bastion',
        hostname: '10.0.0.1',
        createdAt: DateTime.now(),
      ),
    );

    await (source.update(source.hosts)..where((h) => h.id.equals(behindId)))
        .write(const HostsCompanion(jumpHostId: Value(bastionId)));

    // A nested group, same shape.
    await source.into(source.hostGroups).insert(
      HostGroupsCompanion.insert(
        id: 'child-group',
        workspaceId: 'default',
        name: 'child',
      ),
    );

    await source.into(source.hostGroups).insert(
      HostGroupsCompanion.insert(
        id: 'parent-group',
        workspaceId: 'default',
        name: 'parent',
      ),
    );

    await (source.update(source.hostGroups)
          ..where((g) => g.id.equals('child-group')))
        .write(const HostGroupsCompanion(parentId: Value('parent-group')));
  }

  test('a backup with a jump host restores', () async {
    await seedSourceWithForwardReferences();

    final envelope = await sync.exportEncryptedBackup(
      db: source,
      masterPassword: passphrase,
    );

    // Before the fix this threw SqliteException(787) and restored nothing.
    final result = await sync.importEncryptedBackup(
      backupPackageJson: envelope,
      db: target,
      masterPassword: passphrase,
    );

    expect(result.secretsRecovered, isTrue);

    final restored = await target.select(target.hosts).get();
    final byLabel = {for (final h in restored) h.label: h};

    expect(byLabel.keys, containsAll(['bastion', 'mia-master']));
    expect(
      byLabel['mia-master']!.jumpHostId,
      byLabel['bastion']!.id,
      reason: 'The jump host link has to survive the restore, not just the row.',
    );
    expect(byLabel['mia-master']!.port, 22022);
  });

  test('foreign keys are still enforced after the restore commits', () async {
    // Deferring must not leave the connection with checks switched off: the
    // pragma is scoped to the transaction, and a restore that quietly disabled
    // referential integrity afterwards would be a worse bug than the one it
    // fixed.
    await seedSourceWithForwardReferences();

    final envelope = await sync.exportEncryptedBackup(
      db: source,
      masterPassword: passphrase,
    );
    await sync.importEncryptedBackup(
      backupPackageJson: envelope,
      db: target,
      masterPassword: passphrase,
    );

    await expectLater(
      target
          .into(target.hosts)
          .insert(
            HostsCompanion.insert(
              id: 'dangling',
              workspaceId: 'default',
              label: 'dangling',
              hostname: 'nowhere',
              jumpHostId: const Value('no-such-host'),
              createdAt: DateTime.now(),
            ),
          ),
      throwsA(anything),
    );
  });

  test('a nested host group restores with its parent link', () async {
    await seedSourceWithForwardReferences();

    final envelope = await sync.exportEncryptedBackup(
      db: source,
      masterPassword: passphrase,
    );
    await sync.importEncryptedBackup(
      backupPackageJson: envelope,
      db: target,
      masterPassword: passphrase,
    );

    final groups = await target.select(target.hostGroups).get();
    final child = groups.where((g) => g.id == 'child-group').firstOrNull;

    expect(child, isNotNull);
    expect(child!.parentId, 'parent-group');
  });
}
