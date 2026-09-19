import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';
import 'daos/bookmarks_dao.dart';
import 'daos/hosts_dao.dart';
import 'daos/identities_dao.dart';
import 'daos/known_hosts_dao.dart';
import 'daos/mcp_dao.dart';
import 'daos/paired_devices_dao.dart';
import 'daos/runbooks_dao.dart';
import 'daos/snippets_dao.dart';
import 'daos/templates_dao.dart';
import 'daos/tunnels_dao.dart';
import 'daos/workspaces_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Workspaces,
    Identities,
    HostGroups,
    Hosts,
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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 10;

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
      },
    );
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
