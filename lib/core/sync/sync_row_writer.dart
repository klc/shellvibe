import 'package:drift/drift.dart';

import '../../shared/database/app_database.dart';

/// What a write had to do to fit the row it was given.
final class RowWriteResult {
  /// False when the row could not be written at all.
  final bool written;

  /// Reference columns that were cleared because their target is not here.
  final List<String> clearedReferences;

  /// The reference that stopped the write, when [written] is false.
  final String? missingRequirement;

  const RowWriteResult.ok({this.clearedReferences = const []})
    : written = true,
      missingRequirement = null;

  const RowWriteResult.skipped(String requirement)
    : written = false,
      clearedReferences = const [],
      missingRequirement = requirement;
}

/// Writes one decoded row into the database.
///
/// The counterpart of [SyncRowCodec]. Both the snapshot restore and the
/// operation log go through here, so a row cannot land one way when it arrives
/// in a backup and another way when it arrives as an operation.
///
/// Nothing here deletes. Every write is an upsert on the primary key, which is
/// what makes a partial backup safe to restore and a replayed operation
/// harmless.
final class SyncRowWriter {
  const SyncRowWriter._();

  /// Writes [row] of [entityType].
  ///
  /// References are repaired against the database rather than against whatever
  /// batch the row arrived in: an operation or a narrowed backup may point at
  /// a row this device already has, and that reference is good. A nullable
  /// reference whose target is missing is cleared; a required one that is
  /// missing stops the write, because the row cannot exist without it.
  static Future<RowWriteResult> write(
    AppDatabase db,
    String entityType,
    Map<String, Object?> row,
  ) async {
    Future<bool> exists(TableInfo<dynamic, dynamic> table, String? id) async {
      if (id == null) return false;

      final found = await db
          .customSelect(
            'SELECT 1 FROM ${table.actualTableName} WHERE id = ? LIMIT 1',
            variables: [Variable.withString(id)],
          )
          .get();

      return found.isNotEmpty;
    }

    String id() => row['id'] as String;
    String? str(String key) => row[key] as String?;
    DateTime date(String key) => DateTime.parse(row[key] as String);

    switch (entityType) {
      case 'workspaces':
        await db
            .into(db.workspaces)
            .insertOnConflictUpdate(
              WorkspacesCompanion.insert(
                id: id(),
                name: row['name'] as String,
                colorCode: Value(str('colorCode')),
                createdAt: date('createdAt'),
              ),
            );

        return const RowWriteResult.ok();

      case 'identities':
        if (!await exists(db.workspaces, str('workspaceId'))) {
          return const RowWriteResult.skipped('workspace');
        }

        await db
            .into(db.identities)
            .insertOnConflictUpdate(
              IdentitiesCompanion.insert(
                id: id(),
                workspaceId: row['workspaceId'] as String,
                title: row['title'] as String,
                username: row['username'] as String,
                // A row written by a build that still offered the removed SSH
                // agent option would otherwise reintroduce what the v7
                // migration just rewrote.
                authType: normalizeAuthType(row['authType'] as String),
                passwordEncrypted: Value(str('passwordEncrypted')),
                privateKeyEncrypted: Value(str('privateKeyEncrypted')),
                passphraseEncrypted: Value(str('passphraseEncrypted')),
                createdAt: date('createdAt'),
              ),
            );

        return const RowWriteResult.ok();

      case 'host_groups':
        if (!await exists(db.workspaces, str('workspaceId'))) {
          return const RowWriteResult.skipped('workspace');
        }

        // `parentId` points inside this same table, so it cannot be checked
        // while the rows are still arriving. It is left as it is and swept
        // afterwards by [clearDanglingSelfReferences].
        await db
            .into(db.hostGroups)
            .insertOnConflictUpdate(
              HostGroupsCompanion.insert(
                id: id(),
                workspaceId: row['workspaceId'] as String,
                parentId: Value(str('parentId')),
                name: row['name'] as String,
                colorTag: Value(str('colorTag')),
              ),
            );

        return const RowWriteResult.ok();

      case 'hosts':
        if (!await exists(db.workspaces, str('workspaceId'))) {
          return const RowWriteResult.skipped('workspace');
        }

        final cleared = <String>[];

        final identityId = str('identityId');
        final keepIdentity = await exists(db.identities, identityId);
        if (identityId != null && !keepIdentity) cleared.add('identity');

        final groupId = str('groupId');
        final keepGroup = await exists(db.hostGroups, groupId);
        if (groupId != null && !keepGroup) cleared.add('group');

        await db
            .into(db.hosts)
            .insertOnConflictUpdate(
              HostsCompanion.insert(
                id: id(),
                workspaceId: row['workspaceId'] as String,
                groupId: Value(keepGroup ? groupId : null),
                identityId: Value(keepIdentity ? identityId : null),
                label: row['label'] as String,
                hostname: row['hostname'] as String,
                // Absent in rows written before these columns existed; the
                // table's own defaults apply then.
                username: Value(str('username')),
                port: Value(row['port'] as int? ?? 22),
                protocol: Value(str('protocol') ?? 'ssh'),
                moshServerPath: Value(str('moshServerPath')),
                moshPortRange: Value(str('moshPortRange')),
                colorTag: Value(str('colorTag')),
                jumpHostId: Value(str('jumpHostId')),
                environment: Value(str('environment') ?? 'dev'),
                mcpVisible: Value(row['mcpVisible'] as bool? ?? true),
                mcpDefaultMode: Value(str('mcpDefaultMode') ?? 'readonly'),
                createdAt: date('createdAt'),
              ),
            );

        return RowWriteResult.ok(clearedReferences: cleared);

      case 'port_forward_rules':
        // `host_id` is NOT NULL, so a rule without its host is a row that
        // cannot exist.
        if (!await exists(db.hosts, str('hostId'))) {
          return const RowWriteResult.skipped('host');
        }

        await db
            .into(db.portForwardRules)
            .insertOnConflictUpdate(
              PortForwardRulesCompanion.insert(
                id: id(),
                hostId: row['hostId'] as String,
                type: row['type'] as String,
                localPort: row['localPort'] as int,
                remoteHost: Value(str('remoteHost')),
                remotePort: Value(row['remotePort'] as int?),
                autoStart: Value(row['autoStart'] as bool? ?? false),
              ),
            );

        return const RowWriteResult.ok();

      case 'snippets':
        if (!await exists(db.workspaces, str('workspaceId'))) {
          return const RowWriteResult.skipped('workspace');
        }

        await db
            .into(db.snippets)
            .insertOnConflictUpdate(
              SnippetsCompanion.insert(
                id: id(),
                workspaceId: row['workspaceId'] as String,
                title: row['title'] as String,
                code: row['code'] as String,
                tags: Value(str('tags')),
              ),
            );

        return const RowWriteResult.ok();

      case 'runbooks':
        if (!await exists(db.workspaces, str('workspaceId'))) {
          return const RowWriteResult.skipped('workspace');
        }

        await db
            .into(db.runbooks)
            .insertOnConflictUpdate(
              RunbooksCompanion.insert(
                id: id(),
                workspaceId: row['workspaceId'] as String,
                title: row['title'] as String,
                description: Value(str('description')),
                createdAt: date('createdAt'),
              ),
            );

        return const RowWriteResult.ok();

      case 'runbook_steps':
        if (!await exists(db.runbooks, str('runbookId'))) {
          return const RowWriteResult.skipped('runbook');
        }

        await db
            .into(db.runbookSteps)
            .insertOnConflictUpdate(
              RunbookStepsCompanion.insert(
                id: id(),
                runbookId: row['runbookId'] as String,
                stepOrder: row['stepOrder'] as int,
                command: row['command'] as String,
                expectedExitCode: Value(row['expectedExitCode'] as int? ?? 0),
                expectedOutputPattern: Value(str('expectedOutputPattern')),
                timeoutSeconds: Value(row['timeoutSeconds'] as int? ?? 30),
              ),
            );

        return const RowWriteResult.ok();

      case 'templates':
        if (!await exists(db.workspaces, str('workspaceId'))) {
          return const RowWriteResult.skipped('workspace');
        }

        await db
            .into(db.templates)
            .insertOnConflictUpdate(
              TemplatesCompanion.insert(
                id: id(),
                workspaceId: row['workspaceId'] as String,
                name: row['name'] as String,
                description: Value(str('description')),
                activePaneId: Value(str('activePaneId')),
                createdAt: date('createdAt'),
              ),
            );

        return const RowWriteResult.ok();

      case 'template_panes':
        if (!await exists(db.templates, str('templateId'))) {
          return const RowWriteResult.skipped('template');
        }

        // `hostId` here is deliberately not a foreign key: deleting a host
        // must not rewrite a saved layout, and a pane whose host is gone is
        // skipped when the template runs. So it is written as it is.
        await db
            .into(db.templatePanes)
            .insertOnConflictUpdate(
              TemplatePanesCompanion.insert(
                id: id(),
                templateId: row['templateId'] as String,
                paneOrder: row['paneOrder'] as int,
                parentPaneId: Value(str('parentPaneId')),
                splitDirection: Value(str('splitDirection')),
                splitRatio: Value(
                  (row['splitRatio'] as num?)?.toDouble() ?? 0.5,
                ),
                sessionType: row['sessionType'] as String,
                hostId: Value(str('hostId')),
                title: Value(str('title')),
              ),
            );

        return const RowWriteResult.ok();

      case 'bookmarks':
        if (!await exists(db.workspaces, str('workspaceId'))) {
          return const RowWriteResult.skipped('workspace');
        }

        final hostId = str('hostId');
        final templateId = str('templateId');
        final keepHost = await exists(db.hosts, hostId);
        final keepTemplate = await exists(db.templates, templateId);

        // Both targets are nullable, so a bookmark survives losing one. One
        // that loses both points at nothing and is not worth a row.
        if (!keepHost && !keepTemplate) {
          return const RowWriteResult.skipped('host or template');
        }

        await db
            .into(db.bookmarks)
            .insertOnConflictUpdate(
              BookmarksCompanion.insert(
                id: id(),
                workspaceId: row['workspaceId'] as String,
                hostId: Value(keepHost ? hostId : null),
                templateId: Value(keepTemplate ? templateId : null),
                position: Value(row['position'] as int? ?? 0),
                createdAt: date('createdAt'),
              ),
            );

        return const RowWriteResult.ok();

      default:
        throw ArgumentError.value(
          entityType,
          'entityType',
          'Not a writable table',
        );
    }
  }

  /// Deletes one row. Foreign keys cascade from here as they would anywhere.
  static Future<void> deleteRow(
    AppDatabase db,
    String entityType,
    String entityId,
  ) async {
    await db.customStatement(
      'DELETE FROM ${_tableOf(db, entityType).actualTableName} WHERE id = ?',
      [entityId],
    );
  }

  /// Clears self-references that point at rows which never arrived.
  ///
  /// `hosts.jump_host_id` and `host_groups.parent_id` point inside their own
  /// table, so they cannot be checked as the rows arrive. Foreign keys are
  /// deferred to COMMIT during a batch, which means one dangling reference
  /// fails the whole batch -- the failure a jump host produced on a phone on
  /// 2026-09-18. Run this before committing.
  ///
  /// Returns how many rows were changed, by column.
  static Future<Map<String, int>> clearDanglingSelfReferences(
    AppDatabase db,
  ) async {
    final cleared = <String, int>{};

    for (final (table, column) in const [
      ('hosts', 'jump_host_id'),
      ('host_groups', 'parent_id'),
    ]) {
      final counted = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM $table '
            'WHERE $column IS NOT NULL '
            'AND $column NOT IN (SELECT id FROM $table)',
          )
          .getSingle();

      final count = counted.read<int>('n');
      if (count == 0) continue;

      await db.customStatement(
        'UPDATE $table SET $column = NULL '
        'WHERE $column IS NOT NULL '
        'AND $column NOT IN (SELECT id FROM $table)',
      );

      cleared[column] = count;
    }

    return cleared;
  }

  /// Maps auth types this build no longer supports onto `'password'`.
  ///
  /// `'agent'` identities were never usable -- no connection path read them --
  /// so one arriving from elsewhere is treated the way the v7 migration treats
  /// a local leftover.
  static String normalizeAuthType(String authType) =>
      const {'password', 'key'}.contains(authType) ? authType : 'password';

  static TableInfo<dynamic, dynamic> _tableOf(
    AppDatabase db,
    String entityType,
  ) => switch (entityType) {
    'workspaces' => db.workspaces,
    'identities' => db.identities,
    'host_groups' => db.hostGroups,
    'hosts' => db.hosts,
    'port_forward_rules' => db.portForwardRules,
    'snippets' => db.snippets,
    'runbooks' => db.runbooks,
    'runbook_steps' => db.runbookSteps,
    'templates' => db.templates,
    'template_panes' => db.templatePanes,
    'bookmarks' => db.bookmarks,
    _ => throw ArgumentError.value(
      entityType,
      'entityType',
      'Not a writable table',
    ),
  };
}
