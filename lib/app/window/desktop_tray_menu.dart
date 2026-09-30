import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

/// Most rows one tray submenu lists before it says how many it left out.
///
/// An OS menu is not a scrolling list: past a screenful macOS shrinks it into
/// scroll arrows and a Linux indicator may refuse it outright. The full set is
/// one click away in the window.
const int kTrayMenuSubmenuLimit = 10;

/// Longest label the tray shows before cutting it short.
const int _maxLabelLength = 48;

/// Keys of the menu items, shared by the builder and the click handler so the
/// two cannot drift apart. Ids are appended after the colon, and parsed by
/// [TrayAction.parse].
abstract final class TrayKeys {
  static const show = 'show';
  static const quit = 'quit';
  static const tabPrefix = 'tab:';
  static const tunnelStopPrefix = 'tunnel.stop:';
  static const tunnelStartPrefix = 'tunnel.start:';
  static const hostPrefix = 'host:';
  static const templatePrefix = 'template:';
}

/// What a click on a tray menu item asks for, decoded from its key.
sealed class TrayAction {
  const TrayAction();

  /// Decodes [key], or null for a key the menu does not use (a disabled
  /// placeholder, a submenu header).
  static TrayAction? parse(String? key) {
    if (key == null) return null;
    if (key == TrayKeys.show) return const TrayShow();
    if (key == TrayKeys.quit) return const TrayQuit();
    final separator = key.indexOf(':');
    if (separator < 0 || separator == key.length - 1) return null;
    final id = key.substring(separator + 1);
    return switch (key.substring(0, separator + 1)) {
      TrayKeys.tabPrefix => TrayFocusTab(id),
      TrayKeys.tunnelStopPrefix => TrayStopTunnel(id),
      TrayKeys.tunnelStartPrefix => TrayStartTunnel(id),
      TrayKeys.hostPrefix => TrayConnectHost(id),
      TrayKeys.templatePrefix => TrayRunTemplate(id),
      _ => null,
    };
  }
}

class TrayShow extends TrayAction {
  const TrayShow();
}

class TrayQuit extends TrayAction {
  const TrayQuit();
}

class TrayFocusTab extends TrayAction {
  const TrayFocusTab(this.tabId);
  final String tabId;
}

class TrayStopTunnel extends TrayAction {
  const TrayStopTunnel(this.ruleId);
  final String ruleId;
}

class TrayStartTunnel extends TrayAction {
  const TrayStartTunnel(this.ruleId);
  final String ruleId;
}

class TrayConnectHost extends TrayAction {
  const TrayConnectHost(this.hostId);
  final String hostId;
}

class TrayRunTemplate extends TrayAction {
  const TrayRunTemplate(this.templateId);
  final String templateId;
}

/// A terminal session as the tray shows it.
enum TraySessionState { connected, connecting, disconnected }

/// One top-level terminal tab in the Sessions submenu.
@immutable
class TraySession {
  const TraySession({
    required this.tabId,
    required this.title,
    required this.state,
  });

  final String tabId;
  final String title;
  final TraySessionState state;

  @override
  bool operator ==(Object other) =>
      other is TraySession &&
      other.tabId == tabId &&
      other.title == title &&
      other.state == state;

  @override
  int get hashCode => Object.hash(tabId, title, state);
}

/// A tunnel rule, running or not, in the Tunnels submenu.
@immutable
class TrayTunnel {
  const TrayTunnel({required this.ruleId, required this.label});

  final String ruleId;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is TrayTunnel && other.ruleId == ruleId && other.label == label;

  @override
  int get hashCode => Object.hash(ruleId, label);
}

/// A host or a template that a click connects to or runs.
@immutable
class TrayTarget {
  const TrayTarget({required this.id, required this.label});

  final String id;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is TrayTarget && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}

/// Everything the tray menu shows, as plain values.
///
/// Kept apart from the providers it is read from for two reasons: the menu can
/// then be built and tested without the plugin, and two snapshots can be
/// compared, which is how a change to something the menu does not show (a
/// tunnel's transfer speed ticks every second) is told from one it does.
@immutable
class TrayMenuData {
  const TrayMenuData({
    this.locked = false,
    this.sessionCount = 0,
    this.activeTunnelCount = 0,
    this.sessions = const [],
    this.activeTunnels = const [],
    this.idleTunnels = const [],
    this.favoriteHosts = const [],
    this.favoriteTemplates = const [],
    this.templates = const [],
  });

  /// Whether the vault is locked, or not known to be unlocked.
  ///
  /// A menu-bar menu is on screen for anyone at the machine, so while this is
  /// set the menu carries counts only: the lists below are left empty by the
  /// reader, so nothing that names a host can reach the builder at all.
  final bool locked;

  /// How many sessions and running tunnels there are, shown in place of their
  /// names while [locked]. Unused otherwise.
  final int sessionCount;
  final int activeTunnelCount;

  final List<TraySession> sessions;

  /// Forwards that are up; a click stops them.
  final List<TrayTunnel> activeTunnels;

  /// Saved forwards that are not running; a click starts them.
  final List<TrayTunnel> idleTunnels;
  final List<TrayTarget> favoriteHosts;
  final List<TrayTarget> favoriteTemplates;
  final List<TrayTarget> templates;

  @override
  bool operator ==(Object other) =>
      other is TrayMenuData &&
      other.locked == locked &&
      other.sessionCount == sessionCount &&
      other.activeTunnelCount == activeTunnelCount &&
      listEquals(other.sessions, sessions) &&
      listEquals(other.activeTunnels, activeTunnels) &&
      listEquals(other.idleTunnels, idleTunnels) &&
      listEquals(other.favoriteHosts, favoriteHosts) &&
      listEquals(other.favoriteTemplates, favoriteTemplates) &&
      listEquals(other.templates, templates);

  @override
  int get hashCode => Object.hash(
    locked,
    sessionCount,
    activeTunnelCount,
    Object.hashAll(sessions),
    Object.hashAll(activeTunnels),
    Object.hashAll(idleTunnels),
    Object.hashAll(favoriteHosts),
    Object.hashAll(favoriteTemplates),
    Object.hashAll(templates),
  );
}

/// Reads a tunnel as `L 8080 → db:5432`, the way `ssh -L` is written down.
///
/// A remote forward lists the port the server opens first, then the local
/// address it lands on; a dynamic one has no far end, only the SOCKS port.
String tunnelRouteLabel({
  required String type,
  required int localPort,
  String? remoteHost,
  int? remotePort,
}) {
  switch (type) {
    case 'local':
      return 'L $localPort → ${remoteHost ?? '127.0.0.1'}:${remotePort ?? 80}';
    case 'remote':
      return 'R ${remotePort ?? 8080} → ${remoteHost ?? '127.0.0.1'}:$localPort';
    case 'dynamic':
      return 'D $localPort (SOCKS5)';
    default:
      return '$type $localPort';
  }
}

/// The tray menu for [data].
Menu buildTrayMenu(TrayMenuData data) {
  if (data.locked) return _lockedMenu(data);
  return Menu(
    items: [
      MenuItem(key: TrayKeys.show, label: 'Show ShellVibe'),
      MenuItem.separator(),
      _sessionsMenu(data),
      _tunnelsMenu(data),
      MenuItem.separator(),
      _targetsMenu(
        'Favorites',
        empty: 'No favorites',
        hosts: data.favoriteHosts,
        templates: data.favoriteTemplates,
      ),
      _targetsMenu(
        'Templates',
        empty: 'No templates',
        hosts: const [],
        templates: data.templates,
      ),
      MenuItem.separator(),
      MenuItem(key: TrayKeys.quit, label: 'Quit ShellVibe'),
    ],
  );
}

/// What a locked vault leaves: a way to the unlock screen, how much is still
/// running behind it, and Quit. No names, and nothing that acts on a host.
Menu _lockedMenu(TrayMenuData data) {
  final sessions = data.sessionCount;
  final tunnels = data.activeTunnelCount;
  return Menu(
    items: [
      MenuItem(key: TrayKeys.show, label: 'Unlock ShellVibe…'),
      MenuItem.separator(),
      MenuItem(
        label: sessions == 1 ? '1 open session' : '$sessions open sessions',
        disabled: true,
      ),
      MenuItem(
        label: tunnels == 1 ? '1 active tunnel' : '$tunnels active tunnels',
        disabled: true,
      ),
      MenuItem.separator(),
      MenuItem(key: TrayKeys.quit, label: 'Quit ShellVibe'),
    ],
  );
}

MenuItem _sessionsMenu(TrayMenuData data) {
  final sessions = data.sessions;
  return MenuItem.submenu(
    label: 'Sessions (${sessions.length})',
    submenu: Menu(
      items: [
        if (sessions.isEmpty)
          MenuItem(label: 'No open sessions', disabled: true),
        for (final session in sessions.take(kTrayMenuSubmenuLimit))
          MenuItem(
            key: '${TrayKeys.tabPrefix}${session.tabId}',
            label: switch (session.state) {
              TraySessionState.connected => '● ${_clip(session.title)}',
              TraySessionState.connecting =>
                '◌ ${_clip(session.title)} — connecting',
              TraySessionState.disconnected =>
                '○ ${_clip(session.title)} — disconnected',
            },
          ),
        ..._overflow(sessions.length),
      ],
    ),
  );
}

MenuItem _tunnelsMenu(TrayMenuData data) {
  final active = data.activeTunnels;
  final idle = data.idleTunnels;
  return MenuItem.submenu(
    label: active.isEmpty ? 'Tunnels' : 'Tunnels (${active.length} active)',
    submenu: Menu(
      items: [
        if (active.isEmpty && idle.isEmpty)
          MenuItem(label: 'No tunnels', disabled: true),
        for (final tunnel in active.take(kTrayMenuSubmenuLimit))
          MenuItem(
            key: '${TrayKeys.tunnelStopPrefix}${tunnel.ruleId}',
            label: 'Stop  ${_clip(tunnel.label)}',
          ),
        ..._overflow(active.length),
        if (active.isNotEmpty && idle.isNotEmpty) MenuItem.separator(),
        for (final tunnel in idle.take(kTrayMenuSubmenuLimit))
          MenuItem(
            key: '${TrayKeys.tunnelStartPrefix}${tunnel.ruleId}',
            label: 'Start  ${_clip(tunnel.label)}',
          ),
        ..._overflow(idle.length),
      ],
    ),
  );
}

/// A submenu of hosts followed by templates, capped as a whole so a long host
/// list cannot push the templates out of a favorites menu unannounced.
MenuItem _targetsMenu(
  String label, {
  required String empty,
  required List<TrayTarget> hosts,
  required List<TrayTarget> templates,
}) {
  final total = hosts.length + templates.length;
  final shownHosts = hosts.take(kTrayMenuSubmenuLimit).toList();
  final shownTemplates = templates
      .take(kTrayMenuSubmenuLimit - shownHosts.length)
      .toList();
  return MenuItem.submenu(
    label: label,
    submenu: Menu(
      items: [
        if (total == 0) MenuItem(label: empty, disabled: true),
        for (final host in shownHosts)
          MenuItem(
            key: '${TrayKeys.hostPrefix}${host.id}',
            label: _clip(host.label),
          ),
        if (shownHosts.isNotEmpty && shownTemplates.isNotEmpty)
          MenuItem.separator(),
        for (final template in shownTemplates)
          MenuItem(
            key: '${TrayKeys.templatePrefix}${template.id}',
            label: _clip(template.label),
          ),
        ..._overflow(total, shown: shownHosts.length + shownTemplates.length),
      ],
    ),
  );
}

List<MenuItem> _overflow(int total, {int? shown}) {
  final left = total - (shown ?? kTrayMenuSubmenuLimit);
  if (left <= 0) return const [];
  return [MenuItem(label: '+$left more in ShellVibe', disabled: true)];
}

String _clip(String text) {
  final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return oneLine.length <= _maxLabelLength
      ? oneLine
      : '${oneLine.substring(0, _maxLabelLength - 1)}…';
}
