import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'tunnels_dao.g.dart';

@DriftAccessor(tables: [PortForwardRules, Hosts])
class TunnelsDao extends DatabaseAccessor<AppDatabase> with _$TunnelsDaoMixin {
  TunnelsDao(super.db);

  Future<List<PortForwardRule>> getRulesForHost(String hostId) {
    return (select(portForwardRules)..where((tbl) => tbl.hostId.equals(hostId))).get();
  }

  Stream<List<PortForwardRule>> watchRulesForHost(String hostId) {
    return (select(portForwardRules)..where((tbl) => tbl.hostId.equals(hostId))).watch();
  }

  Future<List<PortForwardRule>> getAutoStartRules() {
    return (select(portForwardRules)..where((tbl) => tbl.autoStart.equals(true))).get();
  }

  Future<PortForwardRule?> getRuleById(String id) {
    return (select(portForwardRules)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertRule(PortForwardRulesCompanion rule) => into(portForwardRules).insert(rule);

  Future<bool> updateRule(Insertable<PortForwardRule> rule) => update(portForwardRules).replace(rule);

  Future<int> deleteRule(String id) {
    return (delete(portForwardRules)..where((tbl) => tbl.id.equals(id))).go();
  }
}
