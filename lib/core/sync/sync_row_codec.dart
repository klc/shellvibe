import '../../shared/database/app_database.dart';

/// Turns a database row into the JSON a snapshot or an operation carries.
///
/// One codec for both so the two can never drift apart. A row that arrives in
/// an operation and the same row arriving in a snapshot have to be the same
/// shape, or a device restoring a snapshot and a device replaying the log end
/// up with different databases -- which is a bug that only appears on the
/// device that took the other path.
///
/// `known_hosts` is deliberately absent: host key trust is device-local (ADR
/// 003), so it travels in a snapshot the user explicitly restores and never in
/// the background.
final class SyncRowCodec {
  const SyncRowCodec._();

  /// Tables that take part in automatic sync, in dependency order.
  ///
  /// The order is the order rows must be written in: a host cannot be written
  /// before the workspace it belongs to exists.
  static const List<String> syncableTypes = [
    'workspaces',
    'identities',
    'vault_env_vars',
    'host_groups',
    'hosts',
    'port_forward_rules',
    'snippets',
    'runbooks',
    'runbook_steps',
    'templates',
    'template_panes',
    'bookmarks',
  ];

  static Map<String, dynamic> workspace(Workspace w) => {
    'id': w.id,
    'name': w.name,
    'colorCode': w.colorCode,
    'createdAt': w.createdAt.toIso8601String(),
  };

  static Map<String, dynamic> identity(Identity i) => {
    'id': i.id,
    'workspaceId': i.workspaceId,
    'title': i.title,
    'username': i.username,
    'authType': i.authType,
    'passwordEncrypted': i.passwordEncrypted,
    'privateKeyEncrypted': i.privateKeyEncrypted,
    'passphraseEncrypted': i.passphraseEncrypted,
    'createdAt': i.createdAt.toIso8601String(),
  };

  static Map<String, dynamic> vaultEnvVar(VaultEnvVar v) => {
    'id': v.id,
    'workspaceId': v.workspaceId,
    'name': v.name,
    'valueEncrypted': v.valueEncrypted,
    'createdAt': v.createdAt.toIso8601String(),
  };

  static Map<String, dynamic> hostGroup(HostGroup g) => {
    'id': g.id,
    'workspaceId': g.workspaceId,
    'parentId': g.parentId,
    'name': g.name,
    'colorTag': g.colorTag,
  };

  /// Every column on the table, not a subset.
  ///
  /// `username` was missing once, and a restored host then authenticated as
  /// whoever the SSH client fell back to -- which reads to the user as the key
  /// being broken rather than the backup being incomplete.
  static Map<String, dynamic> host(Host h) => {
    'id': h.id,
    'workspaceId': h.workspaceId,
    'groupId': h.groupId,
    'identityId': h.identityId,
    'label': h.label,
    'hostname': h.hostname,
    'username': h.username,
    'port': h.port,
    'protocol': h.protocol,
    'moshServerPath': h.moshServerPath,
    'moshPortRange': h.moshPortRange,
    'colorTag': h.colorTag,
    'jumpHostId': h.jumpHostId,
    'environment': h.environment,
    'mcpVisible': h.mcpVisible,
    'mcpDefaultMode': h.mcpDefaultMode,
    'createdAt': h.createdAt.toIso8601String(),
  };

  static Map<String, dynamic> knownHost(KnownHost k) => {
    'id': k.id,
    'hostname': k.hostname,
    'port': k.port,
    'keyType': k.keyType,
    'fingerprintSha256': k.fingerprintSha256,
    'firstSeenAt': k.firstSeenAt.toIso8601String(),
  };

  static Map<String, dynamic> portForwardRule(PortForwardRule p) => {
    'id': p.id,
    'hostId': p.hostId,
    'type': p.type,
    'localPort': p.localPort,
    'remoteHost': p.remoteHost,
    'remotePort': p.remotePort,
    'autoStart': p.autoStart,
  };

  static Map<String, dynamic> snippet(Snippet s) => {
    'id': s.id,
    'workspaceId': s.workspaceId,
    'title': s.title,
    'code': s.code,
    'tags': s.tags,
  };

  static Map<String, dynamic> runbook(Runbook r) => {
    'id': r.id,
    'workspaceId': r.workspaceId,
    'title': r.title,
    'description': r.description,
    'createdAt': r.createdAt.toIso8601String(),
  };

  static Map<String, dynamic> runbookStep(RunbookStep rs) => {
    'id': rs.id,
    'runbookId': rs.runbookId,
    'stepOrder': rs.stepOrder,
    'command': rs.command,
    'expectedExitCode': rs.expectedExitCode,
    'expectedOutputPattern': rs.expectedOutputPattern,
    'timeoutSeconds': rs.timeoutSeconds,
  };

  static Map<String, dynamic> template(Template t) => {
    'id': t.id,
    'workspaceId': t.workspaceId,
    'name': t.name,
    'description': t.description,
    'activePaneId': t.activePaneId,
    'createdAt': t.createdAt.toIso8601String(),
  };

  static Map<String, dynamic> templatePane(TemplatePane tp) => {
    'id': tp.id,
    'templateId': tp.templateId,
    'paneOrder': tp.paneOrder,
    'parentPaneId': tp.parentPaneId,
    'splitDirection': tp.splitDirection,
    'splitRatio': tp.splitRatio,
    'sessionType': tp.sessionType,
    'hostId': tp.hostId,
    'title': tp.title,
  };

  static Map<String, dynamic> bookmark(Bookmark b) => {
    'id': b.id,
    'workspaceId': b.workspaceId,
    'hostId': b.hostId,
    'templateId': b.templateId,
    'position': b.position,
    'createdAt': b.createdAt.toIso8601String(),
  };

  /// Reads one row of [entityType] and encodes it, or returns null when the
  /// row is not there.
  ///
  /// Used by the journal, which is handed a table name and an id rather than a
  /// typed row: the call sites are DAO methods that already know both.
  static Future<Map<String, dynamic>?> read(
    AppDatabase db,
    String entityType,
    String entityId,
  ) async {
    Future<Map<String, dynamic>?> one<R>(
      Future<R?> Function() fetch,
      Map<String, dynamic> Function(R row) encode,
    ) async {
      final row = await fetch();

      return row == null ? null : encode(row);
    }

    return switch (entityType) {
      'workspaces' => one(
        () => (db.select(
          db.workspaces,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull(),
        workspace,
      ),
      'identities' => one(
        () => (db.select(
          db.identities,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull(),
        identity,
      ),
      'vault_env_vars' => one(
        () => (db.select(
          db.vaultEnvVars,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull(),
        vaultEnvVar,
      ),
      'host_groups' => one(
        () => (db.select(
          db.hostGroups,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull(),
        hostGroup,
      ),
      'hosts' => one(
        () => (db.select(
          db.hosts,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull(),
        host,
      ),
      'port_forward_rules' => one(
        () => (db.select(
          db.portForwardRules,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull(),
        portForwardRule,
      ),
      'snippets' => one(
        () => (db.select(
          db.snippets,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull(),
        snippet,
      ),
      'runbooks' => one(
        () => (db.select(
          db.runbooks,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull(),
        runbook,
      ),
      'runbook_steps' => one(
        () => (db.select(
          db.runbookSteps,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull(),
        runbookStep,
      ),
      'templates' => one(
        () => (db.select(
          db.templates,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull(),
        template,
      ),
      'template_panes' => one(
        () => (db.select(
          db.templatePanes,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull(),
        templatePane,
      ),
      'bookmarks' => one(
        () => (db.select(
          db.bookmarks,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull(),
        bookmark,
      ),
      // An unknown table is a programming error, not a data condition: the
      // caller passed a name that is not in [syncableTypes].
      _ => throw ArgumentError.value(
        entityType,
        'entityType',
        'Not a syncable table',
      ),
    };
  }
}
