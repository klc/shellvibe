import '../models/terminal_tab_session.dart';
import 'terminal_output_chain.dart';

/// Routes input typed into one selected pane to the sessions of the other
/// selected panes.
///
/// The router does not touch `Terminal.onOutput` itself: it registers an
/// interceptor in each selected pane's [TerminalOutputChain] under a per-pane
/// key. The chain owns the slot, so the interceptor coexists with the mobile
/// extra-keys bar in either install order, is removed cleanly on deselect, and
/// is re-applied over the bridge's new handler after a reconnect.
///
/// Forwarding writes to the *base* handler of each target — the session
/// handler with all interceptors peeled off — so a pane receives each payload
/// exactly once and no cascade can form.
class BroadcastInputRouter {
  /// Chain key for this router's interceptor on a given pane. Distinct per
  /// pane because the interceptor closes over the origin id.
  static Object _key(String paneId) => 'broadcast:$paneId';

  /// Invoked by installed interceptors with the origin pane id and the emitted
  /// data. Set by the notifier to read its *live* selection state, so an
  /// interceptor never goes stale when the selection changes after install.
  void Function(String originId, String data)? forwardCallback;

  /// Brings installed interceptors in line with [selectedIds]: selected panes
  /// get one, everything else has it removed. Idempotent — the notifier calls
  /// this on every selection change and after every (re)connect, and the chain
  /// repairs itself from whatever the bridge last left in the slot.
  void sync({
    required Set<String> selectedIds,
    required List<TerminalTabSession> tabs,
  }) {
    for (final tab in tabs) {
      final id = tab.id;
      if (selectedIds.contains(id)) {
        if (tab.outputChain.has(_key(id))) continue;
        // Innermost, so the bytes forwarded to the other panes are the ones
        // this pane's own session receives — after the extra-keys bar has
        // folded any sticky modifier in, not before.
        tab.outputChain.add(_key(id), (data, next) {
          next(data);
          forwardCallback?.call(id, data);
        }, innermost: true);
      } else {
        tab.outputChain.remove(_key(id));
      }
    }
  }

  /// Writes [data] to every selected pane except [originId], bypassing those
  /// panes' interceptors so the payload is delivered exactly once. Panes
  /// without a live session are skipped.
  void forwardToOthers({
    required String originId,
    required Set<String> selectedIds,
    required List<TerminalTabSession> tabs,
    required String data,
  }) {
    final tabsById = {for (final tab in tabs) tab.id: tab};
    for (final id in selectedIds) {
      if (id == originId) continue;
      tabsById[id]?.outputChain.base?.call(data);
    }
  }

  /// Sends [text] to every selected pane (origin included) through the native
  /// `Terminal.paste` pipeline (control-char sanitize, bracketed-paste
  /// wrapping when the app requested it, and newline conversion), so a
  /// broadcast snippet behaves byte-for-byte like a single-pane paste.
  ///
  /// Each pane's own broadcast interceptor is disabled for the duration of its
  /// paste, so the paste never re-enters broadcasting and no pane receives the
  /// text twice.
  ///
  /// Returns the number of panes that received the text. Panes without a live
  /// session (still connecting, or disconnected) are skipped.
  int sendTextToPanes({
    required Set<String> selectedIds,
    required List<TerminalTabSession> tabs,
    required String text,
  }) {
    final tabsById = {for (final tab in tabs) tab.id: tab};
    var sent = 0;
    for (final id in selectedIds) {
      final tab = tabsById[id];
      if (tab == null || tab.outputChain.base == null) continue;
      tab.outputChain.without(_key(id), () => tab.terminal.paste(text));
      sent++;
    }
    return sent;
  }

  /// Removes every installed interceptor (used on notifier dispose).
  void restoreAll(List<TerminalTabSession> tabs) {
    sync(selectedIds: const {}, tabs: tabs);
  }
}
