import '../../core/network/tunnel_engine.dart';
import '../../features/terminal/domain/models/terminal_tab_session.dart';

/// The part of a tab a drop is read from.
typedef TabLiveness = ({
  String id,
  bool connected,
  TerminalDisconnectCause? cause,
});

/// A session that just went from connected to disconnected.
typedef SessionEnd = ({String id, TerminalDisconnectCause cause});

/// Finds sessions that dropped between one scan and the next.
///
/// It has to remember, because the tab list cannot say it: `isConnected` is a
/// mutable field on a tab object that the old and the new list share, so
/// comparing the two lists sees no change at all. The notifier re-emits the
/// list whenever a tab flips, and each emission is scanned here.
///
/// A drop is a tab that *was* connected, is not now, and carries a cause.
/// Without the cause it would also catch a reconnect, which clears the flag on
/// its way to connecting again, and a tab closed by the user is gone from the
/// list rather than disconnected in it.
class SessionDropDetector {
  final Map<String, bool> _connected = {};

  List<SessionEnd> scan(Iterable<TabLiveness> tabs) {
    final ended = <SessionEnd>[];
    final seen = <String>{};
    for (final tab in tabs) {
      seen.add(tab.id);
      final cause = tab.cause;
      if (_connected[tab.id] == true && !tab.connected && cause != null) {
        ended.add((id: tab.id, cause: cause));
      }
      _connected[tab.id] = tab.connected;
    }
    _connected.removeWhere((id, _) => !seen.contains(id));
    return ended;
  }
}

/// Finds forwards that stopped with an error.
///
/// The engine keeps a failed forward in its list (inactive, with the error) and
/// re-emits the list on every transfer tick, so the same failure arrives over
/// and over. Each is reported once, and again only if the forward came up in
/// between and failed anew. A user's Stop takes the entry out of the list
/// instead, so it never shows up here.
class TunnelFailureDetector {
  final Map<String, String> _reported = {};

  List<ActiveTunnel> scan(Iterable<ActiveTunnel> tunnels) {
    final failed = <ActiveTunnel>[];
    final present = <String>{};
    for (final tunnel in tunnels) {
      final error = tunnel.error;
      present.add(tunnel.ruleId);
      if (tunnel.isActive || error == null) {
        _reported.remove(tunnel.ruleId);
        continue;
      }
      if (_reported[tunnel.ruleId] == error) continue;
      _reported[tunnel.ruleId] = error;
      failed.add(tunnel);
    }
    _reported.removeWhere((id, _) => !present.contains(id));
    return failed;
  }
}
