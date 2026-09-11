import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/snippets/data/repositories/snippets_repository.dart';
import 'package:shellvibe/features/snippets/domain/models/snippet_model.dart';
import 'package:shellvibe/shared/database/app_database.dart';

void main() {
  late AppDatabase db;
  late SnippetsRepository repository;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'ws_1',
        name: 'Default Workspace',
        createdAt: DateTime.now(),
      ),
    );
    repository = SnippetsRepository(db.snippetsDao);
  });

  tearDown(() async {
    await db.close();
  });

  group('SnippetsRepository Unit Tests', () {
    test('Initial snippets list is empty', () async {
      final snippets = await repository.getAllSnippets();
      expect(snippets, isEmpty);
    });

    test('addSnippet inserts and retrieves snippet', () async {
      const snippet = SnippetModel(
        id: 'snip_1',
        workspaceId: 'ws_1',
        title: 'Restart Nginx',
        code: 'systemctl restart nginx',
        tags: ['nginx', 'devops'],
      );

      await repository.addSnippet(snippet);

      final snippets = await repository.getAllSnippets();
      expect(snippets.length, equals(1));
      expect(snippets.first.title, equals('Restart Nginx'));
      expect(snippets.first.code, equals('systemctl restart nginx'));
      expect(snippets.first.tags, containsAll(['nginx', 'devops']));
    });

    test('updateSnippet modifies existing record', () async {
      const snippet = SnippetModel(
        id: 'snip_1',
        workspaceId: 'ws_1',
        title: 'Old Title',
        code: 'ls',
      );

      await repository.addSnippet(snippet);

      const updatedSnippet = SnippetModel(
        id: 'snip_1',
        workspaceId: 'ws_1',
        title: 'New Title',
        code: 'ls -la',
        tags: ['updated'],
      );

      await repository.updateSnippet(updatedSnippet);

      final snippets = await repository.getAllSnippets();
      expect(snippets.length, equals(1));
      expect(snippets.first.title, equals('New Title'));
      expect(snippets.first.code, equals('ls -la'));
      expect(snippets.first.tags, contains('updated'));
    });

    test('deleteSnippet removes snippet', () async {
      const snippet = SnippetModel(
        id: 'snip_1',
        workspaceId: 'ws_1',
        title: 'To Delete',
        code: 'clear',
      );

      await repository.addSnippet(snippet);
      expect((await repository.getAllSnippets()).length, equals(1));

      await repository.deleteSnippet('snip_1');
      expect(await repository.getAllSnippets(), isEmpty);
    });
  });
}
