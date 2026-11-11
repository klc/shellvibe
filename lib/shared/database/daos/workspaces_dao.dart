import 'package:drift/drift.dart';
import '../app_database.dart';
import '../models/workspace_usage.dart';
import '../tables.dart';

part 'workspaces_dao.g.dart';

@DriftAccessor(
  tables: [
    Workspaces,
    Identities,
    HostGroups,
    Hosts,
    PortForwardRules,
    Snippets,
    Runbooks,
  ],
)
class WorkspacesDao extends DatabaseAccessor<AppDatabase>
    with _$WorkspacesDaoMixin {
  WorkspacesDao(super.db);

  Future<List<Workspace>> getAllWorkspaces() {
    return (select(workspaces)..orderBy([
          (tbl) => OrderingTerm.asc(tbl.createdAt),
          (tbl) => OrderingTerm.asc(tbl.name),
        ]))
        .get();
  }

  Future<Workspace?> getWorkspaceById(String id) {
    return (select(
      workspaces,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertWorkspace(WorkspacesCompanion workspace) => db.recordUpsert(
    entityType: 'workspaces',
    entityId: workspace.id.value,
    write: () =>
        into(workspaces).insert(workspace, mode: InsertMode.insertOrIgnore),
  );

  /// Creates workspace [id] when it is missing, so a row can be put in it.
  ///
  /// Recorded for sync like any other new workspace: an unrecorded one would
  /// exist on this device only, and the other devices would skip every row
  /// put in it. A workspace this device deleted is not brought back, under
  /// its id for a name, by a write that arrives late: that throws instead.
  Future<void> ensureWorkspaceExists(String id, {String? name}) async {
    if (await getWorkspaceById(id) != null) return;
    final tombstone =
        await (select(db.syncTombstones)..where(
              (t) => t.entityType.equals('workspaces') & t.entityId.equals(id),
            ))
            .getSingleOrNull();
    if (tombstone != null) {
      throw StateError('Workspace $id was deleted.');
    }
    await insertWorkspace(
      WorkspacesCompanion(
        id: Value(id),
        name: Value(name ?? (id == 'default' ? 'Default Workspace' : id)),
        createdAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> updateWorkspaceName(String id, String name) {
    return db.recordUpsert(
      entityType: 'workspaces',
      entityId: id,
      write: () => (update(workspaces)..where((tbl) => tbl.id.equals(id)))
          .write(WorkspacesCompanion(name: Value(name))),
    );
  }

  Future<WorkspaceUsage> getWorkspaceUsage(String id) async {
    final workspaceHosts = await (select(
      hosts,
    )..where((tbl) => tbl.workspaceId.equals(id))).get();
    final hostIds = workspaceHosts.map((host) => host.id).toList();

    final groups = await (select(
      hostGroups,
    )..where((tbl) => tbl.workspaceId.equals(id))).get();
    final identities = await (select(
      this.identities,
    )..where((tbl) => tbl.workspaceId.equals(id))).get();
    final snippets = await (select(
      this.snippets,
    )..where((tbl) => tbl.workspaceId.equals(id))).get();
    final runbooks = await (select(
      this.runbooks,
    )..where((tbl) => tbl.workspaceId.equals(id))).get();
    final tunnels = hostIds.isEmpty
        ? const <PortForwardRule>[]
        : await (select(
            portForwardRules,
          )..where((tbl) => tbl.hostId.isIn(hostIds))).get();

    return WorkspaceUsage(
      hosts: workspaceHosts.length,
      groups: groups.length,
      identities: identities.length,
      tunnels: tunnels.length,
      snippets: snippets.length,
      runbooks: runbooks.length,
    );
  }

  Future<int> deleteWorkspace(String id) {
    return db.recordDelete(
      entityType: 'workspaces',
      entityId: id,
      write: () => (delete(workspaces)..where((tbl) => tbl.id.equals(id))).go(),
    );
  }
}
