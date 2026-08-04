import 'package:xterm2/xterm.dart';

import '../models/terminal_tab_session.dart';

/// One installed tee: the handler that was in place when the tee went in, and
/// the tee closure itself. The tee is kept so every later operation can check
/// `identical(terminal.onOutput, tee)` — i.e. "is our wrapper still the one
/// installed?" — before trusting [original].
class _InstalledTee {
  final void Function(String) original;
  final void Function(String) tee;

  const _InstalledTee({required this.original, required this.tee});
}

/// Tees each selected pane's [Terminal.onOutput] so input typed into any one
/// of them is forwarded verbatim to the sessions of the other selected panes.
///
/// Why wrapping `onOutput` and not the bridges: `Terminal.onOutput` is a
/// single callback that every bridge already installs on connect (see
/// `TerminalSSHBridge`/`TerminalLocalPtyBridge`). The router stashes that
/// original handler, replaces it with a tee while the pane stays selected,
/// and restores the exact same closure on deselect — so the bridge keeps
/// working unchanged outside broadcast mode.
///
/// The slot is not exclusively ours: a bridge nulls `onOutput` on disconnect
/// and installs a fresh closure on reconnect, and [MobileExtraKeysBar] wraps
/// it too. So a stashed original is only valid while our tee is still the
/// installed handler. Every read and every restore checks that with
/// [identical]; when the check fails the router treats the live handler as a
/// new original and re-installs on top of it.
///
/// Forwarding always targets the *unwrapped* handler, never a tee, so a pane
/// receives each payload exactly once — no cascades or duplicates.
class BroadcastInputRouter {
  /// paneId -> the tee currently installed for that pane plus the handler it
  /// wraps. An entry only means "we installed a tee at some point"; use
  /// [_unwrapped] to find out whether it is still the live handler.
  final Map<String, _InstalledTee> _installed = {};

  /// Invoked by installed tees with the origin pane id and the emitted data.
  /// Set by the notifier to read its *live* selection state, so a tee never
  /// goes stale when the selection changes after installation.
  void Function(String originId, String data)? forwardCallback;

  /// The pane's session handler with our tee peeled off: the stashed original
  /// when our tee is the installed handler, the live `onOutput` otherwise
  /// (bridge reconnected, or somebody else wrapped the slot after us).
  void Function(String)? _unwrapped(TerminalTabSession tab) {
    final live = tab.terminal.onOutput;
    final entry = _installed[tab.id];
    if (entry != null && identical(live, entry.tee)) return entry.original;
    return live;
  }

  /// Wraps [original] in a tee for [tab] and records it in [_installed].
  void _installTee(TerminalTabSession tab, void Function(String) original) {
    final id = tab.id;
    void tee(String data) {
      original(data);
      forwardCallback?.call(id, data);
    }

    _installed[id] = _InstalledTee(original: original, tee: tee);
    tab.terminal.onOutput = tee;
  }

  /// Brings installed tees in line with [selectedIds]:
  /// - selected and connected, with our tee not currently installed => stash
  ///   the live handler and install a tee that writes to the pane's own
  ///   session and forwards to every other selected pane;
  /// - no longer selected => restore the stashed handler, but only if our tee
  ///   is still the installed one (otherwise restoring would clobber whatever
  ///   replaced it — e.g. a fresh bridge handler after a reconnect).
  ///
  /// Panes that are connecting (`onOutput` still null) are skipped here; the
  /// notifier re-syncs once their bridge is wired, which installs the tee.
  ///
  /// Re-running this after a disconnect/reconnect cycle is what repairs a
  /// pane's broadcast: the bridge's new closure is not our tee, so the pane is
  /// re-stashed and re-teed instead of being skipped.
  void sync({
    required Set<String> selectedIds,
    required List<TerminalTabSession> tabs,
  }) {
    final tabsById = {for (final tab in tabs) tab.id: tab};

    // Install (or re-install) tees for selected panes.
    for (final id in selectedIds) {
      final tab = tabsById[id];
      if (tab == null || !tab.isConnected) continue;
      final live = tab.terminal.onOutput;
      if (live == null) continue;
      final entry = _installed[id];
      if (entry != null && identical(live, entry.tee)) continue;
      _installTee(tab, live);
    }

    // Restore tees for deselected or closed panes.
    for (final id in _installed.keys.toList()) {
      if (selectedIds.contains(id)) continue;
      final entry = _installed.remove(id)!;
      final tab = tabsById[id];
      if (tab == null) continue;
      if (identical(tab.terminal.onOutput, entry.tee)) {
        tab.terminal.onOutput = entry.original;
      }
    }
  }

  /// Writes [data] to every selected pane except [originId], using each pane's
  /// unwrapped session handler so the payload is delivered exactly once.
  void forwardToOthers({
    required String originId,
    required Set<String> selectedIds,
    required List<TerminalTabSession> tabs,
    required String data,
  }) {
    final tabsById = {for (final tab in tabs) tab.id: tab};
    for (final id in selectedIds) {
      if (id == originId) continue;
      final tab = tabsById[id];
      if (tab == null) continue;
      _unwrapped(tab)?.call(data);
    }
  }

  /// Sends [text] to every selected pane (origin included) through the native
  /// [Terminal.paste] pipeline (control-char sanitize, bracketed-paste
  /// wrapping when the app requested it, and newline conversion), so a
  /// broadcast snippet behaves byte-for-byte like a single-pane paste.
  ///
  /// Each pane's tee is peeled off for the paste and reinstalled immediately
  /// after, so the paste itself never re-triggers broadcasting (no dupes).
  ///
  /// Returns the number of panes that received the text. Panes without a
  /// session handler (still connecting) are skipped.
  int sendTextToPanes({
    required Set<String> selectedIds,
    required List<TerminalTabSession> tabs,
    required String text,
  }) {
    final tabsById = {for (final tab in tabs) tab.id: tab};
    var sent = 0;
    for (final id in selectedIds) {
      final tab = tabsById[id];
      if (tab == null || tab.terminal.onOutput == null) continue;
      // Peel our tee — if it is actually the installed handler — so paste()
      // lands on the plain output handler.
      final entry = _installed[id];
      final liveTee = entry != null && identical(tab.terminal.onOutput, entry.tee)
          ? entry
          : null;
      if (liveTee != null) {
        _installed.remove(id);
        tab.terminal.onOutput = liveTee.original;
      }
      tab.terminal.paste(text);
      sent++;
      if (liveTee != null) {
        _installTee(tab, liveTee.original);
      }
    }
    return sent;
  }

  /// Restores every installed tee (used on notifier dispose).
  void restoreAll(List<TerminalTabSession> tabs) {
    sync(selectedIds: const {}, tabs: tabs);
  }
}
