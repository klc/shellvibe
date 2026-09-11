import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/providers/database_providers.dart';
import '../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../vault/presentation/notifiers/identities_notifier.dart';
import 'mcp_host_connector.dart';
import 'mcp_session_pool.dart';
import 'terminal_tab_session_mirror.dart';

part 'mcp_providers.g.dart';

/// Provider for [McpHostConnector]. Plain-Dart, no `Ref`/`BuildContext` inside
/// the class itself — see its docstring — so this is only the Riverpod
/// wiring around it.
@riverpod
McpHostConnector mcpHostConnector(Ref ref) {
  return McpHostConnector(
    hostsRepository: ref.watch(hostsRepositoryProvider),
    vaultRepository: ref.watch(vaultRepositoryProvider),
    knownHostsDao: ref.watch(knownHostsDaoProvider),
  );
}

/// Provider for [McpSessionPool].
///
/// Must be `keepAlive`: an autoDispose pool would tear down every open agent
/// session the instant nothing was watching it, e.g. the moment the user
/// navigates away from the AI Access settings screen — killing sessions the
/// agent is actively using for a reason that has nothing to do with them.
@Riverpod(keepAlive: true)
McpSessionPool mcpSessionPool(Ref ref) {
  final pool = McpSessionPool(
    connector: ref.watch(mcpHostConnectorProvider),
    // `read`, not `watch`: the tabs notifier is keepAlive too, and rebuilding
    // the pool because the tab list changed would close every live agent
    // session every time the user opened a terminal.
    mirror: TerminalTabSessionMirror(
      notifier: ref.read(terminalTabsProvider.notifier),
    ),
  );
  ref.onDispose(pool.dispose);
  return pool;
}
