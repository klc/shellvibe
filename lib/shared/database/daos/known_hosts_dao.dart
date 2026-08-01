import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'known_hosts_dao.g.dart';

@DriftAccessor(tables: [KnownHosts])
class KnownHostsDao extends DatabaseAccessor<AppDatabase> with _$KnownHostsDaoMixin {
  KnownHostsDao(super.db);

  Future<KnownHost?> findKnownHost(String hostname, int port) async {
    final list = await (select(knownHosts)
          ..where((tbl) => tbl.hostname.equals(hostname) & tbl.port.equals(port)))
        .get();
    return list.firstOrNull;
  }

  Future<List<KnownHost>> getAllKnownHosts() => select(knownHosts).get();

  Future<int> insertOrUpdateKnownHost(KnownHostsCompanion entry) {
    return into(knownHosts).insertOnConflictUpdate(entry);
  }

  Future<int> deleteKnownHost(String id) {
    return (delete(knownHosts)..where((tbl) => tbl.id.equals(id))).go();
  }
}
