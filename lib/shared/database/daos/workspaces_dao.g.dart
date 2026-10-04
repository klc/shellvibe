// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspaces_dao.dart';

// ignore_for_file: type=lint
mixin _$WorkspacesDaoMixin on DatabaseAccessor<AppDatabase> {
  $WorkspacesTable get workspaces => attachedDatabase.workspaces;
  $IdentitiesTable get identities => attachedDatabase.identities;
  $HostGroupsTable get hostGroups => attachedDatabase.hostGroups;
  $SnippetsTable get snippets => attachedDatabase.snippets;
  $HostsTable get hosts => attachedDatabase.hosts;
  $PortForwardRulesTable get portForwardRules =>
      attachedDatabase.portForwardRules;
  $RunbooksTable get runbooks => attachedDatabase.runbooks;
  WorkspacesDaoManager get managers => WorkspacesDaoManager(this);
}

class WorkspacesDaoManager {
  final _$WorkspacesDaoMixin _db;
  WorkspacesDaoManager(this._db);
  $$WorkspacesTableTableManager get workspaces =>
      $$WorkspacesTableTableManager(_db.attachedDatabase, _db.workspaces);
  $$IdentitiesTableTableManager get identities =>
      $$IdentitiesTableTableManager(_db.attachedDatabase, _db.identities);
  $$HostGroupsTableTableManager get hostGroups =>
      $$HostGroupsTableTableManager(_db.attachedDatabase, _db.hostGroups);
  $$SnippetsTableTableManager get snippets =>
      $$SnippetsTableTableManager(_db.attachedDatabase, _db.snippets);
  $$HostsTableTableManager get hosts =>
      $$HostsTableTableManager(_db.attachedDatabase, _db.hosts);
  $$PortForwardRulesTableTableManager get portForwardRules =>
      $$PortForwardRulesTableTableManager(
        _db.attachedDatabase,
        _db.portForwardRules,
      );
  $$RunbooksTableTableManager get runbooks =>
      $$RunbooksTableTableManager(_db.attachedDatabase, _db.runbooks);
}
