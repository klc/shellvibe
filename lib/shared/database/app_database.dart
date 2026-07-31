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
  ],
  daos: [
    HostsDao,
    IdentitiesDao,
    KnownHostsDao,
    TunnelsDao,
    WorkspacesDao,
    SnippetsDao,
    RunbooksDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON;');
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'terly2.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
