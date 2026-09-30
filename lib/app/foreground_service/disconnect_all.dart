import 'package:flutter/foundation.dart';

import '../../core/network/tunnel_engine.dart';
import '../../features/terminal/domain/models/terminal_tab_session.dart';
import 'foreground_service_state.dart';

/// Ids of the tabs "Disconnect all" closes: every tab root that is connected,
/// and every one still connecting — left alone it would finish dialling a
/// moment after the user asked for everything to end, and start the service
/// over. Split panes go with their root, which is what closing a tab does.
List<String> tabIdsToDisconnect(Iterable<TerminalTabSession> tabs) => [
  for (final tab in tabs)
    if (tab.splitParentId == null && (tab.isConnected || tab.isConnecting))
      tab.id,
];

/// Rule ids of the tunnels "Disconnect all" stops: the ones counted.
List<String> tunnelRuleIdsToStop(Iterable<ActiveTunnel> tunnels) => [
  for (final tunnel in tunnels)
    if (isLiveTunnel(tunnel)) tunnel.ruleId,
];

/// Closes every tab in [tabIds] and stops every tunnel in [ruleIds], through
/// the callbacks the UI's own close and stop buttons use.
///
/// One failing does not spare the rest: "Disconnect all" that stops at the
/// first session it cannot close leaves the others running behind a
/// notification that says they are not. Failures are logged, not thrown, for
/// the same reason nobody is waiting on this — it runs off a notification.
Future<void> disconnectAll({
  required Iterable<String> tabIds,
  required Iterable<String> ruleIds,
  required Future<void> Function(String tabId) closeTab,
  required Future<void> Function(String ruleId) stopTunnel,
}) async {
  for (final id in tabIds.toList()) {
    try {
      await closeTab(id);
    } on Object catch (error) {
      debugPrint('[ForegroundService] could not close tab $id: $error');
    }
  }
  for (final id in ruleIds.toList()) {
    try {
      await stopTunnel(id);
    } on Object catch (error) {
      debugPrint('[ForegroundService] could not stop tunnel $id: $error');
    }
  }
}
