import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'identities_dao.g.dart';

@DriftAccessor(tables: [Identities, Workspaces])
class IdentitiesDao extends DatabaseAccessor<AppDatabase>
    with _$IdentitiesDaoMixin {
  IdentitiesDao(super.db);

  Future<List<Identity>> getAllIdentities() => select(identities).get();

  Future<List<Identity>> getIdentitiesByWorkspace(String workspaceId) {
    return (select(
      identities,
    )..where((tbl) => tbl.workspaceId.equals(workspaceId))).get();
  }

  Future<Identity?> getIdentityById(String id) {
    return (select(
      identities,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertIdentity(IdentitiesCompanion identity) async {
    if (identity.workspaceId.present) {
      await db.workspacesDao.ensureWorkspaceExists(identity.workspaceId.value);
    }

    return db.recordUpsert(
      entityType: 'identities',
      entityId: identity.id.value,
      write: () => into(identities).insert(identity),
    );
  }

  /// Updates an existing identity by id.
  ///
  /// Deliberately not `update.replace`: replace is an UPSERT that would
  /// resurrect a deleted row and clobber `createdAt` on every edit.
  Future<int> updateIdentityById(String id, Insertable<Identity> identity) {
    return db.recordUpsert(
      entityType: 'identities',
      entityId: id,
      write: () => (update(
        identities,
      )..where((tbl) => tbl.id.equals(id))).write(identity),
    );
  }

  Future<int> deleteIdentity(String id) {
    return db.recordDelete(
      entityType: 'identities',
      entityId: id,
      write: () => (delete(identities)..where((tbl) => tbl.id.equals(id))).go(),
    );
  }
}
