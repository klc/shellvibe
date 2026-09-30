import '../../core/network/tunnel_engine.dart';
import '../../features/terminal/domain/models/terminal_tab_session.dart';

/// What the service notification reports: how many terminal sessions are
/// connected and how many tunnels are up. Counts only, never a host label or a
/// tab title — the notification is readable from the lock screen.
///
/// A value type on purpose. The inputs change constantly (every tunnel speed
/// tick re-emits the tunnel list), but the counts almost never do, and this is
/// the thing the rest of the feature compares to tell "nothing to tell the
/// system" from "update the notification".
class ServiceCounts {
  const ServiceCounts({this.sessions = 0, this.tunnels = 0});

  static const ServiceCounts idle = ServiceCounts();

  final int sessions;
  final int tunnels;

  /// Nothing is running, so nothing needs the process kept alive.
  bool get isIdle => sessions == 0 && tunnels == 0;

  @override
  bool operator ==(Object other) =>
      other is ServiceCounts &&
      other.sessions == sessions &&
      other.tunnels == tunnels;

  @override
  int get hashCode => Object.hash(sessions, tunnels);

  @override
  String toString() => 'ServiceCounts(sessions: $sessions, tunnels: $tunnels)';
}

/// Whether [tab] is one session the user would count: the root of a tab that is
/// connected right now.
///
/// Split panes are not counted — a split is one tab to the user, the same unit
/// "close tab" and the tab strip use. A tab still connecting or already
/// dropped holds no live socket worth a foreground service.
bool isLiveSessionTab(TerminalTabSession tab) =>
    tab.splitParentId == null && tab.isConnected;

/// Whether [tunnel] is forwarding. One that failed to come up stays in the
/// engine's list as inactive with an error, which is not something to keep the
/// app alive for.
bool isLiveTunnel(ActiveTunnel tunnel) =>
    tunnel.isActive && tunnel.error == null;

/// The counts for the tabs and tunnels as they stand.
ServiceCounts deriveServiceCounts({
  required Iterable<TerminalTabSession> tabs,
  required Iterable<ActiveTunnel> tunnels,
}) => ServiceCounts(
  sessions: tabs.where(isLiveSessionTab).length,
  tunnels: tunnels.where(isLiveTunnel).length,
);

/// The notification title. The same for every state, and all the lock screen
/// gets to see besides [buildServiceNotificationText].
const String kServiceNotificationTitle = 'ShellVibe';

/// "2 sessions · 1 tunnel". A part that is zero is left out, so a phone with
/// only tunnels reads "3 tunnels" rather than "0 sessions · 3 tunnels".
String buildServiceNotificationText(ServiceCounts counts) {
  final parts = [
    if (counts.sessions > 0) _count(counts.sessions, 'session'),
    if (counts.tunnels > 0) _count(counts.tunnels, 'tunnel'),
  ];
  // Never shown: the service stops at zero. Only here so the function is total.
  if (parts.isEmpty) return 'No active connections';
  return parts.join(' · ');
}

String _count(int n, String noun) => n == 1 ? '1 $noun' : '$n ${noun}s';

/// One step the service has to take to match what is running.
sealed class ServiceCommand {
  const ServiceCommand();
}

/// Bring the service up showing [counts].
final class StartService extends ServiceCommand {
  const StartService(this.counts);
  final ServiceCounts counts;
}

/// Rewrite the notification of the running service to show [counts].
final class UpdateService extends ServiceCommand {
  const UpdateService(this.counts);
  final ServiceCounts counts;
}

/// Take the service down.
final class StopService extends ServiceCommand {
  const StopService();
}

/// The state machine, as a function: what to do to get from [shown] (what the
/// service is displaying, or null when it is not running) to [wanted].
///
/// Null means nothing: equal counts never produce an update, which is what
/// keeps a tunnel's speed ticks from reaching the notification manager.
ServiceCommand? planServiceCommand({
  required ServiceCounts? shown,
  required ServiceCounts wanted,
}) {
  if (wanted.isIdle) return shown == null ? null : const StopService();
  if (shown == null) return StartService(wanted);
  if (shown == wanted) return null;
  return UpdateService(wanted);
}
