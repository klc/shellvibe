import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'snippets_dao.g.dart';

@DriftAccessor(tables: [Snippets])
class SnippetsDao extends DatabaseAccessor<AppDatabase>
    with _$SnippetsDaoMixin {
  SnippetsDao(super.db);

  Future<List<Snippet>> getAllSnippets() => select(snippets).get();

  Stream<List<Snippet>> watchAllSnippets() => select(snippets).watch();

  Future<List<Snippet>> getSnippetsByWorkspace(String workspaceId) {
    return (select(
      snippets,
    )..where((tbl) => tbl.workspaceId.equals(workspaceId))).get();
  }

  Stream<List<Snippet>> watchSnippetsByWorkspace(String workspaceId) {
    return (select(
      snippets,
    )..where((tbl) => tbl.workspaceId.equals(workspaceId))).watch();
  }

  Future<int> insertSnippet(SnippetsCompanion snippet) async {
    if (snippet.workspaceId.present) {
      await db.workspacesDao.ensureWorkspaceExists(snippet.workspaceId.value);
    }

    return db.recordUpsert(
      entityType: 'snippets',
      entityId: snippet.id.value,
      write: () => into(snippets).insert(snippet),
    );
  }

  Future<bool> updateSnippet(SnippetsCompanion snippet) => db.recordUpsert(
    entityType: 'snippets',
    entityId: snippet.id.value,
    write: () => update(snippets).replace(snippet),
  );

  Future<int> deleteSnippet(String id) => db.recordDelete(
    entityType: 'snippets',
    entityId: id,
    write: () => (delete(snippets)..where((tbl) => tbl.id.equals(id))).go(),
  );
}
