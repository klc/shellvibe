import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'snippets_dao.g.dart';

@DriftAccessor(tables: [Snippets])
class SnippetsDao extends DatabaseAccessor<AppDatabase> with _$SnippetsDaoMixin {
  SnippetsDao(super.db);

  Future<List<Snippet>> getAllSnippets() => select(snippets).get();

  Stream<List<Snippet>> watchAllSnippets() => select(snippets).watch();

  Future<List<Snippet>> getSnippetsByWorkspace(String workspaceId) {
    return (select(snippets)..where((tbl) => tbl.workspaceId.equals(workspaceId))).get();
  }

  Stream<List<Snippet>> watchSnippetsByWorkspace(String workspaceId) {
    return (select(snippets)..where((tbl) => tbl.workspaceId.equals(workspaceId))).watch();
  }

  Future<int> insertSnippet(SnippetsCompanion snippet) => into(snippets).insert(snippet);

  Future<bool> updateSnippet(SnippetsCompanion snippet) => update(snippets).replace(snippet);

  Future<int> deleteSnippet(String id) => (delete(snippets)..where((tbl) => tbl.id.equals(id))).go();
}
