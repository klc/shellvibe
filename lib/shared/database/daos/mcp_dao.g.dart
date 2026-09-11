// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_dao.dart';

// ignore_for_file: type=lint
mixin _$McpDaoMixin on DatabaseAccessor<AppDatabase> {
  $WorkspacesTable get workspaces => attachedDatabase.workspaces;
  $McpClientsTable get mcpClients => attachedDatabase.mcpClients;
  $HostGroupsTable get hostGroups => attachedDatabase.hostGroups;
  $IdentitiesTable get identities => attachedDatabase.identities;
  $HostsTable get hosts => attachedDatabase.hosts;
  $McpHostGrantsTable get mcpHostGrants => attachedDatabase.mcpHostGrants;
  $McpPolicyRulesTable get mcpPolicyRules => attachedDatabase.mcpPolicyRules;
  $McpApprovalsTable get mcpApprovals => attachedDatabase.mcpApprovals;
  $McpAuditLogTable get mcpAuditLog => attachedDatabase.mcpAuditLog;
  McpDaoManager get managers => McpDaoManager(this);
}

class McpDaoManager {
  final _$McpDaoMixin _db;
  McpDaoManager(this._db);
  $$WorkspacesTableTableManager get workspaces =>
      $$WorkspacesTableTableManager(_db.attachedDatabase, _db.workspaces);
  $$McpClientsTableTableManager get mcpClients =>
      $$McpClientsTableTableManager(_db.attachedDatabase, _db.mcpClients);
  $$HostGroupsTableTableManager get hostGroups =>
      $$HostGroupsTableTableManager(_db.attachedDatabase, _db.hostGroups);
  $$IdentitiesTableTableManager get identities =>
      $$IdentitiesTableTableManager(_db.attachedDatabase, _db.identities);
  $$HostsTableTableManager get hosts =>
      $$HostsTableTableManager(_db.attachedDatabase, _db.hosts);
  $$McpHostGrantsTableTableManager get mcpHostGrants =>
      $$McpHostGrantsTableTableManager(_db.attachedDatabase, _db.mcpHostGrants);
  $$McpPolicyRulesTableTableManager get mcpPolicyRules =>
      $$McpPolicyRulesTableTableManager(
        _db.attachedDatabase,
        _db.mcpPolicyRules,
      );
  $$McpApprovalsTableTableManager get mcpApprovals =>
      $$McpApprovalsTableTableManager(_db.attachedDatabase, _db.mcpApprovals);
  $$McpAuditLogTableTableManager get mcpAuditLog =>
      $$McpAuditLogTableTableManager(_db.attachedDatabase, _db.mcpAuditLog);
}
