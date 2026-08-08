import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'paired_devices_dao.g.dart';

@DriftAccessor(tables: [PairedDevices])
class PairedDevicesDao extends DatabaseAccessor<AppDatabase>
    with _$PairedDevicesDaoMixin {
  PairedDevicesDao(super.db);

  Future<PairedDevice?> findById(String id) {
    return (select(
      pairedDevices,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
  }

  Future<List<PairedDevice>> getAll() {
    return (select(pairedDevices)..orderBy([
          (table) => OrderingTerm.desc(table.lastSeenAt),
          (table) => OrderingTerm.asc(table.name),
        ]))
        .get();
  }

  Stream<List<PairedDevice>> watchAll() {
    return (select(pairedDevices)..orderBy([
          (table) => OrderingTerm.desc(table.lastSeenAt),
          (table) => OrderingTerm.asc(table.name),
        ]))
        .watch();
  }

  Future<int> upsert(PairedDevicesCompanion entry) {
    return into(pairedDevices).insertOnConflictUpdate(entry);
  }

  Future<int> updateLastSeen(String id, DateTime lastSeenAt) {
    return (update(pairedDevices)..where((table) => table.id.equals(id))).write(
      PairedDevicesCompanion(lastSeenAt: Value(lastSeenAt)),
    );
  }

  Future<int> deleteById(String id) {
    return (delete(pairedDevices)..where((table) => table.id.equals(id))).go();
  }
}
