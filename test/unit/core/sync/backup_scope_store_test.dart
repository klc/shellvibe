import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/sync/backup_scope.dart';
import 'package:shellvibe/core/sync/backup_scope_store.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// The three selections are three answers, not one.
///
/// They were a single preference at first, on the reasoning that "what my
/// backups contain" should not mean two things. That was wrong in use:
/// narrowing the file saved to disk quietly narrowed the cloud vault too, and
/// neither has anything to say about what a background sync should carry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BackupScopeStore store;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    store = BackupScopeStore(storage: SecureStorageService());
  });

  test('everything is backed up until a choice is made', () async {
    // The only safe default: a backup that quietly holds less than the user
    // assumes is discovered at restore time.
    for (final target in BackupTarget.values) {
      expect(await store.read(target), BackupScope.full);
    }
  });

  test('narrowing one target leaves the others alone', () async {
    await store.write(
      BackupTarget.file,
      BackupScope.of(const [BackupCategory.hosts]),
    );

    expect(await store.read(BackupTarget.file).then((s) => s.isFull), isFalse);
    expect(await store.read(BackupTarget.cloud), BackupScope.full);
    expect(await store.read(BackupTarget.autoSync), BackupScope.full);
  });

  test('each target keeps its own selection', () async {
    await store.write(
      BackupTarget.file,
      BackupScope.of(const [BackupCategory.hosts]),
    );
    await store.write(
      BackupTarget.cloud,
      BackupScope.of(const [BackupCategory.snippetsAndRunbooks]),
    );
    await store.write(
      BackupTarget.autoSync,
      BackupScope.of(const [BackupCategory.hosts, BackupCategory.identities]),
    );

    expect((await store.read(BackupTarget.file)).toManifest(), ['hosts']);
    expect((await store.read(BackupTarget.cloud)).toManifest(), ['snippets']);
    expect((await store.read(BackupTarget.autoSync)).toManifest(), [
      'hosts',
      'identities',
    ]);
  });

  test(
    'a selection made before the split is inherited, not discarded',
    () async {
      // A user who had already narrowed their backups must not silently get
      // everything again on the next upgrade.
      FlutterSecureStorage.setMockInitialValues({
        'shellvibe_backup_scope': 'hosts,identities',
      });

      for (final target in BackupTarget.values) {
        expect((await store.read(target)).toManifest(), [
          'hosts',
          'identities',
        ]);
      }
    },
  );

  test(
    'a new choice overrides the inherited one for that target only',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'shellvibe_backup_scope': 'hosts',
      });

      await store.write(BackupTarget.cloud, BackupScope.full);

      expect(await store.read(BackupTarget.cloud), BackupScope.full);
      expect((await store.read(BackupTarget.file)).toManifest(), ['hosts']);
    },
  );

  group('automatic sync', () {
    test('is off until it is switched on', () async {
      // Background sync writes to the account on its own schedule, which is
      // not something to start doing because a feature shipped.
      expect(await store.readAutoSyncEnabled(), isFalse);
    });

    test('remembers being switched on and off', () async {
      await store.writeAutoSyncEnabled(true);
      expect(await store.readAutoSyncEnabled(), isTrue);

      await store.writeAutoSyncEnabled(false);
      expect(await store.readAutoSyncEnabled(), isFalse);
    });

    test('is not implied by its categories', () async {
      // Turning the last category off is a strange way to say "stop syncing",
      // and leaving every category on is a stranger way to start.
      await store.write(BackupTarget.autoSync, BackupScope.full);

      expect(await store.readAutoSyncEnabled(), isFalse);
    });
  });
}
