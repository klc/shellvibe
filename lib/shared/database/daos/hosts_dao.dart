import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'hosts_dao.g.dart';

@DriftAccessor(tables: [Hosts, Identities, HostGroups, Workspaces])
class HostsDao extends DatabaseAccessor<AppDatabase> with _$HostsDaoMixin {
  HostsDao(super.db);

  Future<List<Host>> getAllHosts() => select(hosts).get();

  Future<List<Host>> getHostsByWorkspace(String workspaceId) {
    return (select(
      hosts,
    )..where((tbl) => tbl.workspaceId.equals(workspaceId))).get();
  }

  Stream<List<Host>> watchAllHosts() => select(hosts).watch();

  Stream<List<Host>> watchHostsByWorkspace(String workspaceId) {
    return (select(
      hosts,
    )..where((tbl) => tbl.workspaceId.equals(workspaceId))).watch();
  }

  Future<Host?> getHostById(String id) {
    return (select(hosts)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertHost(HostsCompanion host) async {
    if (host.workspaceId.present) {
      await db.workspacesDao.ensureWorkspaceExists(host.workspaceId.value);
    }
    return into(hosts).insert(host);
  }

  /// Updates an existing host by id.
  ///
  /// Deliberately not `update.replace`: replace is an UPSERT that would
  /// resurrect a deleted row and clobber `createdAt` on every edit.
  Future<int> updateHostById(String id, Insertable<Host> host) {
    return (update(hosts)..where((tbl) => tbl.id.equals(id))).write(host);
  }

  Future<int> deleteHost(String id) {
    return (delete(hosts)..where((tbl) => tbl.id.equals(id))).go();
  }

  // --- Host Groups ---

  Future<List<HostGroup>> getAllHostGroups() => select(hostGroups).get();

  Future<List<HostGroup>> getHostGroupsByWorkspace(String workspaceId) {
    return (select(
      hostGroups,
    )..where((tbl) => tbl.workspaceId.equals(workspaceId))).get();
  }

  Stream<List<HostGroup>> watchAllHostGroups() => select(hostGroups).watch();

  Stream<List<HostGroup>> watchHostGroupsByWorkspace(String workspaceId) {
    return (select(
      hostGroups,
    )..where((tbl) => tbl.workspaceId.equals(workspaceId))).watch();
  }

  Future<HostGroup?> getHostGroupById(String id) {
    return (select(
      hostGroups,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertHostGroup(HostGroupsCompanion group) async {
    if (group.workspaceId.present) {
      await db.workspacesDao.ensureWorkspaceExists(group.workspaceId.value);
    }
    return into(hostGroups).insert(group);
  }

  /// Updates an existing host group by id.
  ///
  /// See [updateHostById] for why this is not `update.replace`.
  Future<int> updateHostGroupById(String id, Insertable<HostGroup> group) {
    return (update(hostGroups)..where((tbl) => tbl.id.equals(id))).write(group);
  }

  Future<int> deleteHostGroup(String id) {
    return (delete(hostGroups)..where((tbl) => tbl.id.equals(id))).go();
  }
}
