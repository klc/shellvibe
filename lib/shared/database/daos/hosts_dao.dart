import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'hosts_dao.g.dart';

@DriftAccessor(tables: [Hosts, Identities, HostGroups, Workspaces])
class HostsDao extends DatabaseAccessor<AppDatabase> with _$HostsDaoMixin {
  HostsDao(super.db);

  Future<List<Host>> getAllHosts() => select(hosts).get();

  Stream<List<Host>> watchAllHosts() => select(hosts).watch();

  Future<List<Host>> getHostsByWorkspace(String workspaceId) {
    return (select(hosts)..where((tbl) => tbl.workspaceId.equals(workspaceId))).get();
  }

  Stream<List<Host>> watchHostsByWorkspace(String workspaceId) {
    return (select(hosts)..where((tbl) => tbl.workspaceId.equals(workspaceId))).watch();
  }

  Future<Host?> getHostById(String id) {
    return (select(hosts)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertHost(HostsCompanion host) => into(hosts).insert(host);

  Future<bool> updateHost(Insertable<Host> host) => update(hosts).replace(host);

  Future<int> deleteHost(String id) {
    return (delete(hosts)..where((tbl) => tbl.id.equals(id))).go();
  }

  // --- Host Groups ---

  Future<List<HostGroup>> getAllHostGroups() => select(hostGroups).get();

  Stream<List<HostGroup>> watchAllHostGroups() => select(hostGroups).watch();

  Future<List<HostGroup>> getHostGroupsByWorkspace(String workspaceId) {
    return (select(hostGroups)..where((tbl) => tbl.workspaceId.equals(workspaceId))).get();
  }

  Stream<List<HostGroup>> watchHostGroupsByWorkspace(String workspaceId) {
    return (select(hostGroups)..where((tbl) => tbl.workspaceId.equals(workspaceId))).watch();
  }

  Future<HostGroup?> getHostGroupById(String id) {
    return (select(hostGroups)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertHostGroup(HostGroupsCompanion group) => into(hostGroups).insert(group);

  Future<bool> updateHostGroup(Insertable<HostGroup> group) => update(hostGroups).replace(group);

  Future<int> deleteHostGroup(String id) {
    return (delete(hostGroups)..where((tbl) => tbl.id.equals(id))).go();
  }
}
