// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_history_dao.dart';

// ignore_for_file: type=lint
mixin _$RunHistoryDaoMixin on DatabaseAccessor<AppDatabase> {
  $WorkspacesTable get workspaces => attachedDatabase.workspaces;
  $RunbookRunsTable get runbookRuns => attachedDatabase.runbookRuns;
  $RunbookRunHostsTable get runbookRunHosts => attachedDatabase.runbookRunHosts;
  $RunbookRunStepsTable get runbookRunSteps => attachedDatabase.runbookRunSteps;
  RunHistoryDaoManager get managers => RunHistoryDaoManager(this);
}

class RunHistoryDaoManager {
  final _$RunHistoryDaoMixin _db;
  RunHistoryDaoManager(this._db);
  $$WorkspacesTableTableManager get workspaces =>
      $$WorkspacesTableTableManager(_db.attachedDatabase, _db.workspaces);
  $$RunbookRunsTableTableManager get runbookRuns =>
      $$RunbookRunsTableTableManager(_db.attachedDatabase, _db.runbookRuns);
  $$RunbookRunHostsTableTableManager get runbookRunHosts =>
      $$RunbookRunHostsTableTableManager(
        _db.attachedDatabase,
        _db.runbookRunHosts,
      );
  $$RunbookRunStepsTableTableManager get runbookRunSteps =>
      $$RunbookRunStepsTableTableManager(
        _db.attachedDatabase,
        _db.runbookRunSteps,
      );
}
