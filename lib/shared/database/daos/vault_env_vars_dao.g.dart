// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_env_vars_dao.dart';

// ignore_for_file: type=lint
mixin _$VaultEnvVarsDaoMixin on DatabaseAccessor<AppDatabase> {
  $WorkspacesTable get workspaces => attachedDatabase.workspaces;
  $VaultEnvVarsTable get vaultEnvVars => attachedDatabase.vaultEnvVars;
  VaultEnvVarsDaoManager get managers => VaultEnvVarsDaoManager(this);
}

class VaultEnvVarsDaoManager {
  final _$VaultEnvVarsDaoMixin _db;
  VaultEnvVarsDaoManager(this._db);
  $$WorkspacesTableTableManager get workspaces =>
      $$WorkspacesTableTableManager(_db.attachedDatabase, _db.workspaces);
  $$VaultEnvVarsTableTableManager get vaultEnvVars =>
      $$VaultEnvVarsTableTableManager(_db.attachedDatabase, _db.vaultEnvVars);
}
