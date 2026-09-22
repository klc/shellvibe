import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'tunnels_dao.g.dart';

@DriftAccessor(tables: [PortForwardRules, Hosts])
class TunnelsDao extends DatabaseAccessor<AppDatabase> with _$TunnelsDaoMixin {
  TunnelsDao(super.db);

  Future<List<PortForwardRule>> getRulesForHost(String hostId) {
    return (select(
      portForwardRules,
    )..where((tbl) => tbl.hostId.equals(hostId))).get();
  }

  Future<List<PortForwardRule>> getRulesByWorkspace(String workspaceId) async {
    final workspaceHosts = await (select(
      hosts,
    )..where((tbl) => tbl.workspaceId.equals(workspaceId))).get();
    final hostIds = workspaceHosts.map((host) => host.id).toList();
    if (hostIds.isEmpty) return const [];
    return (select(
      portForwardRules,
    )..where((tbl) => tbl.hostId.isIn(hostIds))).get();
  }

  Stream<List<PortForwardRule>> watchRulesForHost(String hostId) {
    return (select(
      portForwardRules,
    )..where((tbl) => tbl.hostId.equals(hostId))).watch();
  }

  Future<List<PortForwardRule>> getAutoStartRules() {
    return (select(
      portForwardRules,
    )..where((tbl) => tbl.autoStart.equals(true))).get();
  }

  Future<PortForwardRule?> getRuleById(String id) {
    return (select(
      portForwardRules,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertRule(PortForwardRulesCompanion rule) => db.recordUpsert(
    entityType: 'port_forward_rules',
    entityId: rule.id.value,
    write: () => into(portForwardRules).insert(rule),
  );

  /// Updates a rule.
  ///
  /// Takes the companion rather than a bare [Insertable] so the id is readable
  /// here: the sync journal is keyed by row, and digging the id back out of an
  /// opaque insertable is the kind of thing that works until someone passes a
  /// different implementation.
  Future<bool> updateRule(PortForwardRulesCompanion rule) => db.recordUpsert(
    entityType: 'port_forward_rules',
    entityId: rule.id.value,
    write: () => update(portForwardRules).replace(rule),
  );

  Future<int> deleteRule(String id) {
    return db.recordDelete(
      entityType: 'port_forward_rules',
      entityId: id,
      write: () =>
          (delete(portForwardRules)..where((tbl) => tbl.id.equals(id))).go(),
    );
  }
}
