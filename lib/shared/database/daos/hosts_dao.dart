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

    return db.recordUpsert(
      entityType: 'hosts',
      entityId: host.id.value,
      write: () => into(hosts).insert(host),
    );
  }

  /// Updates an existing host by id.
  ///
  /// Deliberately not `update.replace`: replace is an UPSERT that would
  /// resurrect a deleted row and clobber `createdAt` on every edit.
  Future<int> updateHostById(String id, Insertable<Host> host) {
    return db.recordUpsert(
      entityType: 'hosts',
      entityId: id,
      write: () =>
          (update(hosts)..where((tbl) => tbl.id.equals(id))).write(host),
    );
  }

  Future<int> deleteHost(String id) {
    return db.recordDelete(
      entityType: 'hosts',
      entityId: id,
      write: () => (delete(hosts)..where((tbl) => tbl.id.equals(id))).go(),
    );
  }

  /// Points every host in [hostIds] at [identityId] in a single statement.
  ///
  /// Deliberately not a loop over [updateHostById] with a full companion: that
  /// would require the caller to hold a current copy of every other column and
  /// would rewrite them all, so a stale copy would silently undo unrelated
  /// edits. Only `identityId` is written here.
  ///
  /// A null [identityId] detaches the hosts. Returns the number of rows changed.
  Future<int> assignIdentityToHosts(
    List<String> hostIds,
    String? identityId,
  ) async {
    if (hostIds.isEmpty) return 0;

    // One statement, but one operation per host: the sync log is keyed by
    // row, and a bulk write that recorded nothing would leave every other
    // device pointing at the old identity.
    return transaction(() async {
      final changed =
          await (update(hosts)..where((tbl) => tbl.id.isIn(hostIds))).write(
            HostsCompanion(identityId: Value<String?>(identityId)),
          );

      for (final id in hostIds) {
        await db.recordUpsert(
          entityType: 'hosts',
          entityId: id,
          write: () async {},
        );
      }

      return changed;
    });
  }

  /// Moves every host currently bound to [fromIdentityId] onto [toIdentityId].
  ///
  /// Used before deleting an identity: the foreign key is `ON DELETE SET NULL`,
  /// so once the row is gone the binding is unrecoverable.
  Future<int> reassignIdentity(
    String fromIdentityId,
    String? toIdentityId,
  ) async {
    return transaction(() async {
      final affected = await (select(
        hosts,
      )..where((tbl) => tbl.identityId.equals(fromIdentityId))).get();

      final changed =
          await (update(hosts)
                ..where((tbl) => tbl.identityId.equals(fromIdentityId)))
              .write(HostsCompanion(identityId: Value<String?>(toIdentityId)));

      for (final host in affected) {
        await db.recordUpsert(
          entityType: 'hosts',
          entityId: host.id,
          write: () async {},
        );
      }

      return changed;
    });
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

    return db.recordUpsert(
      entityType: 'host_groups',
      entityId: group.id.value,
      write: () => into(hostGroups).insert(group),
    );
  }

  /// Updates an existing host group by id.
  ///
  /// See [updateHostById] for why this is not `update.replace`.
  Future<int> updateHostGroupById(String id, Insertable<HostGroup> group) {
    return db.recordUpsert(
      entityType: 'host_groups',
      entityId: id,
      write: () =>
          (update(hostGroups)..where((tbl) => tbl.id.equals(id))).write(group),
    );
  }

  Future<int> deleteHostGroup(String id) {
    return db.recordDelete(
      entityType: 'host_groups',
      entityId: id,
      write: () => (delete(hostGroups)..where((tbl) => tbl.id.equals(id))).go(),
    );
  }
}
