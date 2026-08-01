import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'identities_dao.g.dart';

@DriftAccessor(tables: [Identities, Workspaces])
class IdentitiesDao extends DatabaseAccessor<AppDatabase> with _$IdentitiesDaoMixin {
  IdentitiesDao(super.db);

  Future<List<Identity>> getAllIdentities() => select(identities).get();

  Stream<List<Identity>> watchAllIdentities() => select(identities).watch();

  Future<List<Identity>> getIdentitiesByWorkspace(String workspaceId) {
    return (select(identities)..where((tbl) => tbl.workspaceId.equals(workspaceId))).get();
  }

  Stream<List<Identity>> watchIdentitiesByWorkspace(String workspaceId) {
    return (select(identities)..where((tbl) => tbl.workspaceId.equals(workspaceId))).watch();
  }

  Future<Identity?> getIdentityById(String id) {
    return (select(identities)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertIdentity(IdentitiesCompanion identity) async {
    if (identity.workspaceId.present) {
      await db.workspacesDao.ensureWorkspaceExists(identity.workspaceId.value);
    }
    return into(identities).insert(identity);
  }

  Future<bool> updateIdentity(Insertable<Identity> identity) => update(identities).replace(identity);

  Future<int> deleteIdentity(String id) {
    return (delete(identities)..where((tbl) => tbl.id.equals(id))).go();
  }
}
