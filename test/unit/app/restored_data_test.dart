import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/restored_data.dart';
import 'package:shellvibe/features/bookmarks/presentation/notifiers/bookmarks_notifier.dart';
import 'package:shellvibe/features/templates/presentation/notifiers/templates_notifier.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/vault_env_vars_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

/// Hands the test a [Ref] to call [invalidateRestoredData] with, the way the
/// backup and sync notifiers do.
final _restore = Provider<void Function()>(
  (ref) =>
      () => invalidateRestoredData(ref),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  // A restore writes rows straight into the tables. Every list the backup
  // payload carries has to be re-read afterwards, or it shows what was there
  // before until the app restarts.
  test(
    're-reads templates, bookmarks and vault env vars after a restore',
    () async {
      // Held the way the screens hold them; an unwatched auto-dispose list
      // would re-read on its own and hide a missing invalidation.
      container.listen(templatesProvider, (_, _) {});
      container.listen(bookmarksProvider, (_, _) {});
      container.listen(vaultEnvVarsProvider, (_, _) {});

      expect(await container.read(templatesProvider.future), isEmpty);
      expect(await container.read(bookmarksProvider.future), isEmpty);
      expect(await container.read(vaultEnvVarsProvider.future), isEmpty);

      final now = DateTime.now();
      await db
          .into(db.templates)
          .insert(
            TemplatesCompanion.insert(
              id: 't1',
              workspaceId: 'default',
              name: 'two panes',
              createdAt: now,
            ),
          );
      await db
          .into(db.bookmarks)
          .insert(
            BookmarksCompanion.insert(
              id: 'b1',
              workspaceId: 'default',
              templateId: const Value('t1'),
              createdAt: now,
            ),
          );
      await db
          .into(db.vaultEnvVars)
          .insert(
            VaultEnvVarsCompanion.insert(
              id: 'e1',
              workspaceId: 'default',
              name: 'TOKEN',
              valueEncrypted: 'sealed',
              createdAt: now,
            ),
          );

      container.read(_restore)();

      expect(
        (await container.read(templatesProvider.future)).map((t) => t.id),
        ['t1'],
      );
      expect(
        (await container.read(bookmarksProvider.future)).map((b) => b.id),
        ['b1'],
      );
      expect(
        (await container.read(vaultEnvVarsProvider.future)).map((v) => v.name),
        ['TOKEN'],
      );
    },
  );
}
