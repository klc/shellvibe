import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'workspaces_dao.g.dart';

@DriftAccessor(tables: [Workspaces])
class WorkspacesDao extends DatabaseAccessor<AppDatabase> with _$WorkspacesDaoMixin {
  WorkspacesDao(super.db);

  Future<List<Workspace>> getAllWorkspaces() => select(workspaces).get();

  Stream<List<Workspace>> watchAllWorkspaces() => select(workspaces).watch();

  Future<Workspace?> getWorkspaceById(String id) {
    return (select(workspaces)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertWorkspace(WorkspacesCompanion workspace) => into(workspaces).insert(workspace);

  Future<bool> updateWorkspace(Insertable<Workspace> workspace) => update(workspaces).replace(workspace);

  Future<int> deleteWorkspace(String id) {
    return (delete(workspaces)..where((tbl) => tbl.id.equals(id))).go();
  }
}
