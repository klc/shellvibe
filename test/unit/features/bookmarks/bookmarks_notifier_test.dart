import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/features/bookmarks/presentation/notifiers/bookmarks_notifier.dart';
import 'package:shellvibe/features/hosts/presentation/notifiers/hosts_notifier.dart';
import 'package:shellvibe/features/templates/domain/models/template_model.dart';
import 'package:shellvibe/features/templates/presentation/notifiers/templates_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<String> addHost(String label) async {
    final host = await container
        .read(hostsProvider.notifier)
        .addHost(
          workspaceId: 'default',
          label: label,
          hostname: '$label.internal',
        );
    return host.id;
  }

  group('BookmarksNotifier', () {
    test('toggling a host stars it, and toggling again removes it', () async {
      final hostId = await addHost('web');
      final notifier = container.read(bookmarksProvider.notifier);
      await container.read(bookmarksProvider.future);

      await notifier.toggleHost(hostId);
      expect(notifier.isHostBookmarked(hostId), isTrue);
      expect(container.read(bookmarksProvider).value, hasLength(1));

      await notifier.toggleHost(hostId);
      expect(notifier.isHostBookmarked(hostId), isFalse);
      expect(container.read(bookmarksProvider).value, isEmpty);
    });

    test('bookmarks come back in the order they were added', () async {
      final first = await addHost('alpha');
      final second = await addHost('bravo');
      final third = await addHost('charlie');
      final notifier = container.read(bookmarksProvider.notifier);
      await container.read(bookmarksProvider.future);

      // Added out of alphabetical order on purpose: a bookmark list is the
      // user's order, not the host list's.
      await notifier.toggleHost(third);
      await notifier.toggleHost(first);
      await notifier.toggleHost(second);

      final ids = container
          .read(bookmarksProvider)
          .value!
          .map((bookmark) => bookmark.hostId)
          .toList();
      expect(ids, equals([third, first, second]));
    });

    test('deleting a host takes its bookmark with it', () async {
      final hostId = await addHost('doomed');
      final notifier = container.read(bookmarksProvider.notifier);
      await container.read(bookmarksProvider.future);
      await notifier.toggleHost(hostId);
      expect(container.read(bookmarksProvider).value, hasLength(1));

      await container.read(hostsProvider.notifier).deleteHost(hostId);
      container.invalidate(bookmarksProvider);

      // The row is gone by foreign key, not by a sweep in the delete path, so
      // nothing is left pointing at a host that no longer exists.
      expect(await container.read(bookmarksProvider.future), isEmpty);
    });

    test('a template can be bookmarked alongside hosts', () async {
      final hostId = await addHost('web');
      final template = TemplateModel(
        id: 'tpl-1',
        workspaceId: 'default',
        name: 'Morning layout',
        panes: const [],
        createdAt: DateTime.utc(2026),
      );
      await container
          .read(templatesRepositoryProvider)
          .addTemplate(template);
      final notifier = container.read(bookmarksProvider.notifier);
      await container.read(bookmarksProvider.future);

      await notifier.toggleHost(hostId);
      await notifier.toggleTemplate(template.id);

      expect(notifier.isTemplateBookmarked(template.id), isTrue);
      final bookmarks = container.read(bookmarksProvider).value!;
      expect(bookmarks, hasLength(2));
      expect(bookmarks.first.hostId, equals(hostId));
      expect(bookmarks.last.templateId, equals(template.id));
    });
  });
}
