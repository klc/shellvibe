import 'package:drift/drift.dart';
import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/tunnels_dao.dart';
import '../../domain/models/tunnel_rule_model.dart';
import '../../domain/repositories/tunnel_repository.dart';

/// Implementation of [TunnelRepository] that wraps [TunnelsDao] and maps between Drift entities and domain models.
class TunnelRepositoryImpl implements TunnelRepository {
  final TunnelsDao _dao;

  TunnelRepositoryImpl(this._dao);

  @override
  Future<List<TunnelRuleModel>> getAllRules() async {
    final rules = await (_dao.select(_dao.portForwardRules)).get();
    return rules.map(_mapToDomain).toList();
  }

  @override
  Future<List<TunnelRuleModel>> getRulesByWorkspace(String workspaceId) async {
    final rules = await _dao.getRulesByWorkspace(workspaceId);
    return rules.map(_mapToDomain).toList();
  }

  @override
  Future<List<TunnelRuleModel>> getRulesForHost(String hostId) async {
    final rules = await _dao.getRulesForHost(hostId);
    return rules.map(_mapToDomain).toList();
  }

  @override
  Future<TunnelRuleModel?> getRuleById(String id) async {
    final rule = await _dao.getRuleById(id);
    return rule != null ? _mapToDomain(rule) : null;
  }

  @override
  Future<List<TunnelRuleModel>> getAutoStartRules() async {
    final rules = await _dao.getAutoStartRules();
    return rules.map(_mapToDomain).toList();
  }

  @override
  Stream<List<TunnelRuleModel>> watchRulesForHost(String hostId) {
    return _dao
        .watchRulesForHost(hostId)
        .map((rules) => rules.map(_mapToDomain).toList());
  }

  @override
  Future<void> addRule(TunnelRuleModel rule) async {
    await _dao.insertRule(_mapToCompanion(rule));
  }

  @override
  Future<void> updateRule(TunnelRuleModel rule) async {
    await _dao.updateRule(_mapToCompanion(rule));
  }

  @override
  Future<void> deleteRule(String id) async {
    await _dao.deleteRule(id);
  }

  TunnelRuleModel _mapToDomain(PortForwardRule entity) {
    return TunnelRuleModel(
      id: entity.id,
      hostId: entity.hostId,
      type: entity.type,
      localPort: entity.localPort,
      remoteHost: entity.remoteHost,
      remotePort: entity.remotePort,
      autoStart: entity.autoStart,
    );
  }

  PortForwardRulesCompanion _mapToCompanion(TunnelRuleModel model) {
    return PortForwardRulesCompanion(
      id: Value(model.id),
      hostId: Value(model.hostId),
      type: Value(model.type),
      localPort: Value(model.localPort),
      remoteHost: Value(model.remoteHost),
      remotePort: Value(model.remotePort),
      autoStart: Value(model.autoStart),
    );
  }
}
