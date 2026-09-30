import 'package:flutter/foundation.dart';

import '../../features/hosts/domain/models/host_model.dart';

/// Shortcut type for "connect to this host"; the host id follows the colon.
const String kHostShortcutPrefix = 'host:';

/// Shortcut type for a new local terminal. Desktop builds only ever show it.
const String kLocalTerminalShortcutType = 'local_terminal';

/// Shortcut type for the host picker.
const String kQuickConnectShortcutType = 'quick_connect';

/// iOS shows four shortcuts in all and ignores the rest; Android launchers
/// show four to five. The list is trimmed to the smaller so what is offered is
/// what is seen, rather than whatever the platform happens to drop.
const int kMaxAppShortcuts = 4;

/// How many of those places hosts may take, leaving one for the picker.
const int kMaxHostShortcuts = 3;

/// One entry of the app-icon menu, as plain data.
///
/// Kept apart from the plugin's own `ShortcutItem` so the list can be built,
/// compared and tested without the plugin, and so a rebuild that produced the
/// same list can be recognised and not sent to the platform again.
@immutable
class AppShortcut {
  final String type;
  final String title;
  final String? subtitle;

  const AppShortcut({required this.type, required this.title, this.subtitle});

  @override
  bool operator ==(Object other) =>
      other is AppShortcut &&
      other.type == type &&
      other.title == title &&
      other.subtitle == subtitle;

  @override
  int get hashCode => Object.hash(type, title, subtitle);

  @override
  String toString() => 'AppShortcut($type, $title)';
}

/// What the user asked for by pressing a shortcut.
sealed class QuickAction {
  const QuickAction();
}

/// Connect to the saved host with [hostId].
final class ConnectHostAction extends QuickAction {
  final String hostId;

  const ConnectHostAction(this.hostId);

  @override
  bool operator ==(Object other) =>
      other is ConnectHostAction && other.hostId == hostId;

  @override
  int get hashCode => hostId.hashCode;
}

/// Open a shell on this machine.
final class OpenLocalTerminalAction extends QuickAction {
  const OpenLocalTerminalAction();
}

/// Open the host picker.
final class QuickConnectAction extends QuickAction {
  const QuickConnectAction();
}

/// The type string a shortcut for [hostId] carries.
String hostShortcutType(String hostId) => '$kHostShortcutPrefix$hostId';

/// Reads a shortcut type string back into an action.
///
/// Null for a type this build does not know — one an older or newer version
/// registered, which the platform may still be showing — and for a host
/// shortcut with no id. Both are ignored rather than guessed at.
QuickAction? parseQuickActionType(String type) {
  if (type == kQuickConnectShortcutType) return const QuickConnectAction();
  if (type == kLocalTerminalShortcutType) {
    return const OpenLocalTerminalAction();
  }
  if (type.startsWith(kHostShortcutPrefix)) {
    final hostId = type.substring(kHostShortcutPrefix.length);
    return hostId.isEmpty ? null : ConnectHostAction(hostId);
  }
  return null;
}

/// Builds the app-icon menu.
///
/// Hosts come from the bookmarks, in the order the user arranged them — the
/// app keeps no connection history to rank by, and adding one would mean a
/// schema migration for a convenience. A bookmark whose host is gone is
/// skipped, as is a host with no bookmark.
///
/// [locked] withholds the hosts. Host names are what the vault's lock screen
/// exists to keep private, and the menu is readable from the home screen
/// without unlocking anything, so a locked app offers only the picker.
List<AppShortcut> buildAppShortcuts({
  required List<HostModel> hosts,
  required List<String> bookmarkedHostIds,
  bool locked = false,
  bool supportsLocalTerminal = false,
  int maxHosts = kMaxHostShortcuts,
  int maxTotal = kMaxAppShortcuts,
}) {
  final generic = <AppShortcut>[
    if (supportsLocalTerminal)
      const AppShortcut(
        type: kLocalTerminalShortcutType,
        title: 'New local terminal',
      ),
    const AppShortcut(type: kQuickConnectShortcutType, title: 'Quick connect'),
  ];
  if (locked) return generic;

  final byId = {for (final host in hosts) host.id: host};
  final seen = <String>{};
  final room = (maxTotal - generic.length).clamp(0, maxHosts);
  final hostShortcuts = <AppShortcut>[];
  for (final id in bookmarkedHostIds) {
    if (hostShortcuts.length >= room) break;
    final host = byId[id];
    if (host == null || !seen.add(id)) continue;
    // A phone has no local shell, and a "local" host would open nothing.
    if (host.protocol == 'local' && !supportsLocalTerminal) continue;
    hostShortcuts.add(
      AppShortcut(
        type: hostShortcutType(host.id),
        title: host.label,
        subtitle: host.hostname,
      ),
    );
  }
  return [...hostShortcuts, ...generic];
}
