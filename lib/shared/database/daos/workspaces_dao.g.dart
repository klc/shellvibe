// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspaces_dao.dart';

// ignore_for_file: type=lint
mixin _$WorkspacesDaoMixin on DatabaseAccessor<AppDatabase> {
  $WorkspacesTable get workspaces => attachedDatabase.workspaces;
  WorkspacesDaoManager get managers => WorkspacesDaoManager(this);
}

class WorkspacesDaoManager {
  final _$WorkspacesDaoMixin _db;
  WorkspacesDaoManager(this._db);
  $$WorkspacesTableTableManager get workspaces =>
      $$WorkspacesTableTableManager(_db.attachedDatabase, _db.workspaces);
}
