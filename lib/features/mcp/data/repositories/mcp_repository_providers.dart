import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/providers/database_providers.dart';
import 'mcp_approval_repository.dart';
import 'mcp_audit_repository.dart';
import 'mcp_client_repository.dart';
import 'mcp_grant_repository.dart';

part 'mcp_repository_providers.g.dart';

/// Auto-disposing provider for [McpClientRepository].
@riverpod
McpClientRepository mcpClientRepository(Ref ref) {
  return McpClientRepository(ref.watch(mcpDaoProvider));
}

/// Auto-disposing provider for [McpGrantRepository].
@riverpod
McpGrantRepository mcpGrantRepository(Ref ref) {
  return McpGrantRepository(ref.watch(mcpDaoProvider));
}

/// Auto-disposing provider for [McpApprovalRepository].
@riverpod
McpApprovalRepository mcpApprovalRepository(Ref ref) {
  return McpApprovalRepository(ref.watch(mcpDaoProvider));
}

/// Auto-disposing provider for [McpAuditRepository].
@riverpod
McpAuditRepository mcpAuditRepository(Ref ref) {
  return McpAuditRepository(ref.watch(mcpDaoProvider));
}
