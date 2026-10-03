// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hosts_dao.dart';

// ignore_for_file: type=lint
mixin _$HostsDaoMixin on DatabaseAccessor<AppDatabase> {
  $WorkspacesTable get workspaces => attachedDatabase.workspaces;
  $HostGroupsTable get hostGroups => attachedDatabase.hostGroups;
  $IdentitiesTable get identities => attachedDatabase.identities;
  $SnippetsTable get snippets => attachedDatabase.snippets;
  $HostsTable get hosts => attachedDatabase.hosts;
  $HostGroupMembersTable get hostGroupMembers =>
      attachedDatabase.hostGroupMembers;
  HostsDaoManager get managers => HostsDaoManager(this);
}

class HostsDaoManager {
  final _$HostsDaoMixin _db;
  HostsDaoManager(this._db);
  $$WorkspacesTableTableManager get workspaces =>
      $$WorkspacesTableTableManager(_db.attachedDatabase, _db.workspaces);
  $$HostGroupsTableTableManager get hostGroups =>
      $$HostGroupsTableTableManager(_db.attachedDatabase, _db.hostGroups);
  $$IdentitiesTableTableManager get identities =>
      $$IdentitiesTableTableManager(_db.attachedDatabase, _db.identities);
  $$SnippetsTableTableManager get snippets =>
      $$SnippetsTableTableManager(_db.attachedDatabase, _db.snippets);
  $$HostsTableTableManager get hosts =>
      $$HostsTableTableManager(_db.attachedDatabase, _db.hosts);
  $$HostGroupMembersTableTableManager get hostGroupMembers =>
      $$HostGroupMembersTableTableManager(
        _db.attachedDatabase,
        _db.hostGroupMembers,
      );
}
