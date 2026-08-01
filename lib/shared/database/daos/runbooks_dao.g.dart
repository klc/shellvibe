// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runbooks_dao.dart';

// ignore_for_file: type=lint
mixin _$RunbooksDaoMixin on DatabaseAccessor<AppDatabase> {
  $WorkspacesTable get workspaces => attachedDatabase.workspaces;
  $RunbooksTable get runbooks => attachedDatabase.runbooks;
  $RunbookStepsTable get runbookSteps => attachedDatabase.runbookSteps;
  RunbooksDaoManager get managers => RunbooksDaoManager(this);
}

class RunbooksDaoManager {
  final _$RunbooksDaoMixin _db;
  RunbooksDaoManager(this._db);
  $$WorkspacesTableTableManager get workspaces =>
      $$WorkspacesTableTableManager(_db.attachedDatabase, _db.workspaces);
  $$RunbooksTableTableManager get runbooks =>
      $$RunbooksTableTableManager(_db.attachedDatabase, _db.runbooks);
  $$RunbookStepsTableTableManager get runbookSteps =>
      $$RunbookStepsTableTableManager(_db.attachedDatabase, _db.runbookSteps);
}
