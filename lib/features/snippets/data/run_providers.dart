import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/providers/database_providers.dart';
import '../../mcp/data/mcp_providers.dart';
import '../domain/services/remote_command_session.dart';
import '../domain/services/runbook_run_service.dart';
import 'repositories/run_history_repository.dart';
import 'services/ssh_remote_command_session_factory.dart';

part 'run_providers.g.dart';

/// Where background runs get their sessions. The seam widget tests override
/// with a fake so no test (and no un-wired build) can reach a socket or pretend
/// a command ran.
@riverpod
RemoteCommandSessionFactory remoteCommandSessionFactory(Ref ref) {
  return SshRemoteCommandSessionFactory(
    connector: ref.watch(mcpHostConnectorProvider),
  );
}

@riverpod
RunbookRunService runbookRunService(Ref ref) {
  return RunbookRunService(
    sessionFactory: ref.watch(remoteCommandSessionFactoryProvider),
  );
}

/// Local run history (never synced). Overridable in tests.
@riverpod
RunHistoryRepository runHistoryRepository(Ref ref) {
  return RunHistoryRepository(ref.watch(appDatabaseProvider).runHistoryDao);
}
