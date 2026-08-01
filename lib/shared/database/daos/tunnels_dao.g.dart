// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tunnels_dao.dart';

// ignore_for_file: type=lint
mixin _$TunnelsDaoMixin on DatabaseAccessor<AppDatabase> {
  $WorkspacesTable get workspaces => attachedDatabase.workspaces;
  $HostGroupsTable get hostGroups => attachedDatabase.hostGroups;
  $IdentitiesTable get identities => attachedDatabase.identities;
  $HostsTable get hosts => attachedDatabase.hosts;
  $PortForwardRulesTable get portForwardRules =>
      attachedDatabase.portForwardRules;
  TunnelsDaoManager get managers => TunnelsDaoManager(this);
}

class TunnelsDaoManager {
  final _$TunnelsDaoMixin _db;
  TunnelsDaoManager(this._db);
  $$WorkspacesTableTableManager get workspaces =>
      $$WorkspacesTableTableManager(_db.attachedDatabase, _db.workspaces);
  $$HostGroupsTableTableManager get hostGroups =>
      $$HostGroupsTableTableManager(_db.attachedDatabase, _db.hostGroups);
  $$IdentitiesTableTableManager get identities =>
      $$IdentitiesTableTableManager(_db.attachedDatabase, _db.identities);
  $$HostsTableTableManager get hosts =>
      $$HostsTableTableManager(_db.attachedDatabase, _db.hosts);
  $$PortForwardRulesTableTableManager get portForwardRules =>
      $$PortForwardRulesTableTableManager(
        _db.attachedDatabase,
        _db.portForwardRules,
      );
}
