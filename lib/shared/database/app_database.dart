import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../core/sync/sync_journal.dart';
import 'tables.dart';
import 'daos/bookmarks_dao.dart';
import 'daos/hosts_dao.dart';
import 'daos/identities_dao.dart';
import 'daos/known_hosts_dao.dart';
import 'daos/mcp_dao.dart';
import 'daos/paired_devices_dao.dart';
import 'daos/run_history_dao.dart';
import 'daos/runbooks_dao.dart';
import 'daos/snippets_dao.dart';
import 'daos/templates_dao.dart';
import 'daos/tunnels_dao.dart';
import 'daos/vault_env_vars_dao.dart';
import 'daos/workspaces_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Workspaces,
    Identities,
    HostGroups,
    Hosts,
    HostGroupMembers,
    KnownHosts,
    PortForwardRules,
    Snippets,
    Runbooks,
    RunbookSteps,
    Templates,
    TemplatePanes,
    PairedDevices,
    McpClients,
    McpHostGrants,
    McpPolicyRules,
    McpApprovals,
    McpAuditLog,
    Bookmarks,
    PendingOperations,
    SyncTombstones,
    SyncState,
    SyncEntityVersions,
    VaultEnvVars,
    RunbookRuns,
    RunbookRunHosts,
    RunbookRunSteps,
  ],
  daos: [
    HostsDao,
    IdentitiesDao,
    KnownHostsDao,
    TunnelsDao,
    WorkspacesDao,
    SnippetsDao,
    RunbooksDao,
    TemplatesDao,
    PairedDevicesDao,
    McpDao,
    BookmarksDao,
    VaultEnvVarsDao,
    RunHistoryDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  /// Records local changes for automatic sync, when it is switched on.
  ///
  /// Null until a vault is set up. The DAOs call through [recordUpsert] and
  /// [recordDelete] either way, so nothing in them has to know whether sync
  /// exists -- and a device that turns sync on does not need a different write
  /// path than one that never does.
  SyncJournal? syncJournal;

  /// Runs [write] and records it, when there is a journal to record into.
  Future<T> recordUpsert<T>({
    required String entityType,
    required String entityId,
    required Future<T> Function() write,
  }) {
    final journal = syncJournal;

    return journal == null
        ? write()
        : journal.upsert(
            entityType: entityType,
            entityId: entityId,
            write: write,
          );
  }

  /// Runs [write], which deletes the row, and records it along with everything
  /// the database cascades or rewrites.
  Future<T> recordDelete<T>({
    required String entityType,
    required String entityId,
    required Future<T> Function() write,
  }) {
    final journal = syncJournal;

    return journal == null
        ? write()
        : journal.delete(
            entityType: entityType,
            entityId: entityId,
            write: write,
          );
  }

  @override
  int get schemaVersion => 18;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON;');
        final workspaceTableExists = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          variables: [Variable.withString(workspaces.actualTableName)],
        ).get();
        if (workspaceTableExists.isNotEmpty) {
          await into(workspaces).insert(
            WorkspacesCompanion.insert(
              id: 'default',
              name: 'Default Workspace',
              createdAt: DateTime.now(),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await m.addColumn(hosts, hosts.username);
        }
        if (from < 3) {
          await _migrateHostKeyFingerprints();
        }
        if (from < 4) {
          await m.createTable(templates);
          await m.createTable(templatePanes);
        }
        if (from < 5) {
          // Both nullable: an existing host keeps using the mosh defaults, and
          // the `protocol` column it may already carry is left untouched.
          await m.addColumn(hosts, hosts.moshServerPath);
          await m.addColumn(hosts, hosts.moshPortRange);
        }
        if (from < 6) {
          await m.createTable(pairedDevices);
        }
        if (from < 7) {
          await _migrateAgentIdentities();
        }
        if (from < 8) {
          // All three columns carry defaults, so existing host rows stay
          // valid untouched; new fields start at the most restrictive value
          // ('readonly') rather than opening access silently.
          await m.addColumn(hosts, hosts.environment);
          await m.addColumn(hosts, hosts.mcpVisible);
          await m.addColumn(hosts, hosts.mcpDefaultMode);
          await m.createTable(mcpClients);
          await m.createTable(mcpHostGrants);
          await m.createTable(mcpPolicyRules);
          await m.createTable(mcpApprovals);
          await m.createTable(mcpAuditLog);
        }
        if (from < 9) {
          await m.createTable(bookmarks);
        }
        if (from < 10) {
          // The local outbox for automatic sync. Empty on an existing
          // install: nothing that happened before this migration was
          // recorded, and the first snapshot is what carries it instead.
          await m.createTable(pendingOperations);
          await m.createTable(syncTombstones);
          await m.createTable(syncState);
        }
        if (from < 11) {
          // Which clock each row stands at. Empty on an existing install:
          // every row is then treated as having no version, so the first
          // operation for it wins -- which is correct, because a device that
          // has never synced has nothing to defend.
          await m.createTable(syncEntityVersions);
        }
        if (from >= 10 && from < 12) {
          // How far a join got. `none` on an existing install, including one
          // that is already syncing: it joined under the old flow, which had
          // no seed step, so telling it the join is finished would be a claim
          // about rows that were never sent.
          //
          // Only when the table is already there. An install older than 10
          // gets it from `createTable` above, which builds the table as it is
          // defined now -- column included -- and adding it again fails the
          // whole upgrade with `duplicate column name`.
          await m.addColumn(syncState, syncState.joinState);
        }
        if (from < 13) {
          // Vault-stored environment variables for local shells. Empty on an
          // existing install: nothing wrote this table before it existed.
          await m.createTable(vaultEnvVars);
        }
        if (from >= 10 && from < 14) {
          // Null on an existing install: the first pull after the upgrade
          // starts from the clock cursor and the server answers with a
          // position. Only above 10, for the same reason as `joinState`.
          await m.addColumn(syncState, syncState.pulledThroughSeq);
        }
        if (from < 15) {
          // A host can carry several tags now. Every existing single tag
          // becomes a membership row, with the same deterministic id
          // (`hostId:groupId`) that sync uses, so two devices upgrading the
          // same data produce identical rows instead of duplicates.
          await m.createTable(hostGroupMembers);
          // Only when `hosts` is there: very old databases predate it, and
          // there is then nothing to convert.
          final hostsTable = await customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
            variables: [Variable.withString(hosts.actualTableName)],
          ).get();
          if (hostsTable.isNotEmpty) {
            await customStatement(
              'INSERT OR IGNORE INTO host_group_members '
              '(id, host_id, group_id) '
              "SELECT id || ':' || group_id, id, group_id FROM hosts "
              'WHERE group_id IS NOT NULL',
            );
            // The legacy column is no longer the source of truth; clearing it
            // stops it from disagreeing with the membership rows.
            await customStatement('UPDATE hosts SET group_id = NULL');
          }
        }
        if (from < 16) {
          // Run history (local only) plus the runbook policy columns, which
          // sync. The columns are added only where the table exists: a
          // database old enough to lack `runbooks` gets it, columns included,
          // from an earlier step's `createTable`, which builds the current
          // definition.
          await m.createTable(runbookRuns);
          await m.createTable(runbookRunHosts);
          await m.createTable(runbookRunSteps);
          if (await _needsColumn(runbooks.actualTableName, 'default_host_ids')) {
            await m.addColumn(runbooks, runbooks.defaultHostIds);
          }
          if (await _needsColumn(runbookSteps.actualTableName, 'on_failure')) {
            await m.addColumn(runbookSteps, runbookSteps.onFailure);
            await m.addColumn(runbookSteps, runbookSteps.retries);
          }
        }
        if (from < 17) {
          // Run history stored the values typed into `${INPUT:...}` prompts,
          // in a file that is not encrypted. Rewrite what is there to names
          // only, and mask the values where they were echoed into commands,
          // output and errors.
          await _scrubRunHistoryValues();

          // Startup snippets and template "on open" runbooks. Nullable
          // references, so every existing row simply has none. Only where the
          // table exists, for the same reason as v16. The two tables they
          // point at are created first if somehow absent: SQLite refuses to
          // write a row whose foreign key names a table that is not there.
          await _ensureTable(snippets);
          await _ensureTable(runbooks);
          if (await _needsColumn(hosts.actualTableName, 'startup_snippet_id')) {
            await m.addColumn(hosts, hosts.startupSnippetId);
          }
          if (await _needsColumn(
            templates.actualTableName,
            'on_open_runbook_id',
          )) {
            await m.addColumn(templates, templates.onOpenRunbookId);
            await m.addColumn(templates, templates.onOpenConfirm);
          }
          if (await _needsColumn(
            templatePanes.actualTableName,
            'startup_snippet_id',
          )) {
            await m.addColumn(templatePanes, templatePanes.startupSnippetId);
          }
        }
        if (from < 18) {
          // Step kinds, typed variables, runbook tags and a snippet's own run
          // history. Every column is nullable or defaulted, so existing rows
          // keep meaning what they meant. Where the table exists, as before.
          await _ensureTable(snippets);
          if (await _needsColumn(snippets.actualTableName, 'variables')) {
            await m.addColumn(snippets, snippets.variables);
          }
          if (await _needsColumn(runbooks.actualTableName, 'variables')) {
            await m.addColumn(runbooks, runbooks.variables);
          }
          if (await _needsColumn(runbooks.actualTableName, 'tags')) {
            await m.addColumn(runbooks, runbooks.tags);
          }
          if (await _needsColumn(runbookSteps.actualTableName, 'kind')) {
            await m.addColumn(runbookSteps, runbookSteps.kind);
            await m.addColumn(runbookSteps, runbookSteps.snippetId);
          }
          if (await _needsColumn(runbookRuns.actualTableName, 'snippet_id')) {
            await m.addColumn(runbookRuns, runbookRuns.snippetId);
          }
        }
      },
    );
  }

  /// Rewrites every history row that holds input values (a JSON object) to
  /// hold only their names, replacing each value found in the stored commands
  /// with its `${INPUT:name}` placeholder and in output / errors with
  /// `[redacted]`. Exact matches only; rows already in the name-array form
  /// are left alone.
  Future<void> _scrubRunHistoryValues() async {
    final tables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
      "('runbook_runs', 'runbook_run_hosts', 'runbook_run_steps')",
    ).get();
    if (tables.length < 3) return;

    final runs = await customSelect(
      'SELECT id, variable_values FROM runbook_runs',
    ).get();
    for (final run in runs) {
      final runId = run.read<String>('id');
      Object? decoded;
      try {
        decoded = jsonDecode(run.read<String>('variable_values'));
      } catch (_) {
        decoded = null;
      }
      if (decoded is List) continue;

      final values = <String, String>{
        if (decoded is Map)
          for (final e in decoded.entries) '${e.key}': '${e.value}',
      };
      await customStatement(
        'UPDATE runbook_runs SET variable_values = ? WHERE id = ?',
        [jsonEncode(values.keys.toList()..sort()), runId],
      );
      final secrets = values.entries.where((e) => e.value.isNotEmpty).toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length));
      if (secrets.isEmpty) continue;

      final steps = await customSelect(
        'SELECT s.id, s.command, s.output, s.error FROM runbook_run_steps s '
        'JOIN runbook_run_hosts h ON h.id = s.run_host_id WHERE h.run_id = ?',
        variables: [Variable.withString(runId)],
      ).get();
      for (final step in steps) {
        var command = step.read<String>('command');
        var output = step.read<String>('output');
        var error = step.read<String?>('error');
        for (final secret in secrets) {
          command = command.replaceAll(
            secret.value,
            '\${INPUT:${secret.key}}',
          );
          output = output.replaceAll(secret.value, '[redacted]');
          error = error?.replaceAll(secret.value, '[redacted]');
        }
        await customStatement(
          'UPDATE runbook_run_steps SET command = ?, output = ?, error = ? '
          'WHERE id = ?',
          [command, output, error, step.read<String>('id')],
        );
      }
    }
  }

  /// Creates [table] when the database does not have it. Only an install old
  /// enough to predate it can lack one, and it then gets the current shape.
  Future<void> _ensureTable(TableInfo<Table, dynamic> table) async {
    final found = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(table.actualTableName)],
    ).get();
    if (found.isEmpty) await createMigrator().createTable(table);
  }

  /// True when [table] exists but has no [column] yet: the one case where the
  /// v16 `addColumn` is both possible and needed.
  Future<bool> _needsColumn(String table, String column) async {
    final info = await customSelect('PRAGMA table_info("$table")').get();
    return info.isNotEmpty && !info.any((r) => r.read<String>('name') == column);
  }

  /// Rewrites identities stored with the removed `'agent'` auth type to
  /// `'password'`.
  ///
  /// The SSH agent option was only ever a form choice: no connection path read
  /// it, so those rows could never authenticate. They are rewritten instead of
  /// deleted, keeping the title and username the user typed — the credential
  /// fields were already empty for this auth type.
  Future<void> _migrateAgentIdentities() async {
    final existing = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(identities.actualTableName)],
    ).get();
    if (existing.isEmpty) return;

    await customStatement(
      "UPDATE ${identities.actualTableName} "
      "SET auth_type = 'password' WHERE auth_type = 'agent'",
    );
  }

  /// Rewrites `known_hosts` fingerprints stored in the pre-v3 double-encoded
  /// form (`base64(utf8("SHA256:…"))`) to the plain `SHA256:…` string.
  ///
  /// Without this every previously trusted host would be reported as a key
  /// mismatch. Rows that do not decode to a well-formed fingerprint are left
  /// untouched rather than deleted, so nothing is lost if the guess is wrong.
  Future<void> _migrateHostKeyFingerprints() async {
    // Very old databases predate the table entirely; nothing to rewrite there.
    final existing = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(knownHosts.actualTableName)],
    ).get();
    if (existing.isEmpty) return;

    final rows = await select(knownHosts).get();
    for (final row in rows) {
      final decoded = _decodeLegacyFingerprint(row.fingerprintSha256);
      if (decoded == null) continue;
      await (update(knownHosts)..where((t) => t.id.equals(row.id))).write(
        KnownHostsCompanion(fingerprintSha256: Value(decoded)),
      );
    }
  }

  static String? _decodeLegacyFingerprint(String stored) {
    if (stored.startsWith('SHA256:')) return null; // already migrated
    try {
      final decoded = utf8.decode(base64.decode(stored));
      return decoded.startsWith('SHA256:') ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'shellvibe.sqlite'));
    final legacyFile = File(p.join(dbFolder.path, 'terly2.sqlite'));
    if (!await file.exists() && await legacyFile.exists()) {
      try {
        await legacyFile.rename(file.path);
      } catch (_) {
        return NativeDatabase.createInBackground(legacyFile);
      }
    }
    return NativeDatabase.createInBackground(file);
  });
}
