import '../models/tunnel_rule_model.dart';

/// Contract interface for managing Port Forwarding rules.
abstract class TunnelRepository {
  Future<List<TunnelRuleModel>> getAllRules();
  Future<List<TunnelRuleModel>> getRulesForHost(String hostId);
  Future<TunnelRuleModel?> getRuleById(String id);
  Future<List<TunnelRuleModel>> getAutoStartRules();
  Stream<List<TunnelRuleModel>> watchRulesForHost(String hostId);
  Future<void> addRule(TunnelRuleModel rule);
  Future<void> updateRule(TunnelRuleModel rule);
  Future<void> deleteRule(String id);
}
