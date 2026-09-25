import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'vault_env_vars_dao.g.dart';

@DriftAccessor(tables: [VaultEnvVars, Workspaces])
class VaultEnvVarsDao extends DatabaseAccessor<AppDatabase>
    with _$VaultEnvVarsDaoMixin {
  VaultEnvVarsDao(super.db);

  Future<List<VaultEnvVar>> getByWorkspace(String workspaceId) {
    return (select(
      vaultEnvVars,
    )..where((tbl) => tbl.workspaceId.equals(workspaceId))).get();
  }

  Stream<List<VaultEnvVar>> watchByWorkspace(String workspaceId) {
    return (select(
      vaultEnvVars,
    )..where((tbl) => tbl.workspaceId.equals(workspaceId))).watch();
  }

  Future<VaultEnvVar?> getById(String id) {
    return (select(
      vaultEnvVars,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<int> insert(VaultEnvVarsCompanion row) async {
    if (row.workspaceId.present) {
      await db.workspacesDao.ensureWorkspaceExists(row.workspaceId.value);
    }

    return db.recordUpsert(
      entityType: 'vault_env_vars',
      entityId: row.id.value,
      write: () => into(vaultEnvVars).insert(row),
    );
  }

  /// Updates an existing row by id.
  ///
  /// Deliberately not `update.replace`: replace is an UPSERT that would
  /// resurrect a deleted row and clobber `createdAt` on every edit.
  Future<int> updateById(String id, Insertable<VaultEnvVar> row) {
    return db.recordUpsert(
      entityType: 'vault_env_vars',
      entityId: id,
      write: () =>
          (update(vaultEnvVars)..where((tbl) => tbl.id.equals(id))).write(row),
    );
  }

  Future<int> deleteById(String id) {
    return db.recordDelete(
      entityType: 'vault_env_vars',
      entityId: id,
      write: () =>
          (delete(vaultEnvVars)..where((tbl) => tbl.id.equals(id))).go(),
    );
  }
}
