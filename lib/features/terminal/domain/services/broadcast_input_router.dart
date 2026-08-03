import 'package:xterm2/xterm.dart';

import '../models/terminal_tab_session.dart';

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
/// Forwarding always targets the *stashed* (unwrapped) handlers, never a tee,
/// so a pane receives each payload exactly once — no cascades or duplicates.
class BroadcastInputRouter {
  /// paneId -> original `onOutput` handler captured before the tee was
  /// installed. Restored verbatim on deselect or dispose.
  final Map<String, void Function(String)> _stashedOriginals = {};

  /// Invoked by installed tees with the origin pane id and the emitted data.
  /// Set by the notifier to read its *live* selection state, so a tee never
  /// goes stale when the selection changes after installation.
  void Function(String originId, String data)? forwardCallback;

  /// Brings installed tees in line with [selectedIds]:
  /// - selected, connected, and not yet stashed => stash the original handler
  ///   and install a tee that writes to the pane's own session and forwards
  ///   to every other selected pane;
  /// - no longer selected but stashed => restore the original handler.
  ///
  /// Panes that are connecting (`onOutput` still null) are skipped here; the
  /// notifier re-syncs once their bridge is wired, which installs the tee.
  void sync({
    required Set<String> selectedIds,
    required List<TerminalTabSession> tabs,
  }) {
    final tabsById = {for (final tab in tabs) tab.id: tab};

    // Install tees for newly selected panes.
    for (final id in selectedIds) {
      if (_stashedOriginals.containsKey(id)) continue;
      final tab = tabsById[id];
      if (tab == null || !tab.isConnected) continue;
      final original = tab.terminal.onOutput;
      if (original == null) continue;
      _stashedOriginals[id] = original;
      tab.terminal.onOutput = (String data) {
        original(data);
        forwardCallback?.call(id, data);
      };
    }

    // Restore tees for deselected or closed panes.
    for (final id in _stashedOriginals.keys.toList()) {
      if (selectedIds.contains(id)) continue;
      final tab = tabsById[id];
      if (tab == null) {
        _stashedOriginals.remove(id);
        continue;
      }
      final original = _stashedOriginals.remove(id);
      tab.terminal.onOutput = original;
    }
  }

  /// Writes [data] to every selected pane except [originId], using each
  /// pane's unwrapped session handler (the stashed original when a tee is
  /// installed, the live `onOutput` otherwise).
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
      final handler = _stashedOriginals[id] ?? tab.terminal.onOutput;
      handler?.call(data);
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
      // Peel the tee so paste() lands on the plain output handler.
      final original = _stashedOriginals.remove(id);
      if (original != null) tab.terminal.onOutput = original;
      tab.terminal.paste(text);
      sent++;
      if (original != null) {
        // Reinstall the tee exactly as sync() would have built it.
        _stashedOriginals[id] = original;
        tab.terminal.onOutput = (String data) {
          original(data);
          forwardCallback?.call(id, data);
        };
      }
    }
    return sent;
  }

  /// Restores every installed tee (used on notifier dispose).
  void restoreAll(List<TerminalTabSession> tabs) {
    sync(selectedIds: const {}, tabs: tabs);
  }
}
