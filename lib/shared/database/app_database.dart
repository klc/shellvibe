import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';
import 'daos/hosts_dao.dart';
import 'daos/identities_dao.dart';
import 'daos/known_hosts_dao.dart';
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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 4;

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
      },
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
    final file = File(p.join(dbFolder.path, 'terly2.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
