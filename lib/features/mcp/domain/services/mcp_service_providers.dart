import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../data/repositories/mcp_repository_providers.dart';
import 'approval_coordinator.dart';
import 'policy_engine.dart';

part 'mcp_service_providers.g.dart';

/// Auto-disposing provider for [PolicyEngine].
///
/// [PolicyEngine] itself holds no mutable state between calls — it is safe
/// to rebuild whenever its repository dependencies change.
@riverpod
PolicyEngine policyEngine(Ref ref) {
  return PolicyEngine(
    grants: ref.watch(mcpGrantRepositoryProvider),
    approvals: ref.watch(mcpApprovalRepositoryProvider),
    dao: ref.watch(mcpDaoProvider),
  );
}

/// Provider for [ApprovalCoordinator].
///
/// Must be `keepAlive`: an autoDispose coordinator would drop a pending
/// approval — and the agent-side `Future` waiting on it — the instant
/// nothing happened to be watching it, e.g. the moment the approval dialog
/// that triggered the watch gets rebuilt or navigated away from. The
/// coordinator has to outlive any single screen; only the panic button and
/// a vault lock (via [ApprovalCoordinator.cancelAll]) get to end a pending
/// approval early.
@Riverpod(keepAlive: true)
ApprovalCoordinator approvalCoordinator(Ref ref) {
  final coordinator = ApprovalCoordinator();
  ref.onDispose(coordinator.dispose);
  return coordinator;
}
