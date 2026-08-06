import 'package:xterm3/xterm.dart';

/// An interceptor link: receives the data heading for the session and decides
/// what (if anything) to pass to [next], the rest of the chain.
typedef OutputInterceptor = void Function(
  String data,
  void Function(String data) next,
);

class _Link {
  _Link(this.key, this.intercept);

  final Object key;
  final OutputInterceptor intercept;
  bool enabled = true;
}

/// Owns a terminal's `onOutput` slot on behalf of several features.
///
/// [Terminal.onOutput] is a single callback, but more than one feature wants a
/// say in what user input does: the SSH/PTY bridge writes it to the session,
/// [BroadcastInputRouter] copies it to other panes, and the mobile extra-keys
/// bar folds sticky modifiers into it. Letting each one wrap whatever it found
/// in the slot cannot work — the wrappers nest in install order, nobody can
/// remove a link that something else has since wrapped, and a bridge that
/// reassigns the slot on reconnect silently drops the lot.
///
/// So the chain keeps the *base* (the bridge's own handler) and an ordered
/// list of interceptors, and installs exactly one closure of its own. Links
/// are added and removed by key, in any order, at any time.
///
/// The bridge is still free to assign `onOutput` directly and does: every
/// operation first checks whether the installed closure is still the live one
/// and, if not, adopts whatever it finds as the new base. A (re)connect
/// therefore repairs the chain rather than breaking it.
///
/// While the base is null (disconnected, or not yet connected) the chain stays
/// dormant and leaves `onOutput` null, so `onOutput == null` keeps meaning
/// "this pane cannot accept input".
class TerminalOutputChain {
  TerminalOutputChain(this.terminal);

  final Terminal terminal;

  /// Innermost first: `_links.last` sees the data before anyone else and
  /// `_links.first` hands it to [_base].
  final List<_Link> _links = [];

  /// The session handler, with every interceptor peeled off.
  void Function(String)? _base;

  /// The closure this chain last put in the slot, used to tell our own
  /// installation apart from somebody else's assignment.
  void Function(String)? _installed;

  /// The session handler with every interceptor peeled off, or null when the
  /// pane has no live session. Writing to it delivers input to the session
  /// exactly once and triggers no interceptor.
  void Function(String)? get base {
    _adopt();
    return _base;
  }

  /// True when a link with [key] is currently in the chain.
  bool has(Object key) => _links.any((l) => l.key == key);

  /// Adds (or replaces, by [key]) an interceptor. The most recently added link
  /// runs first, so a later feature sees the data before the earlier ones.
  ///
  /// Pass [innermost] to pin the link directly against the session instead, so
  /// it sees the data exactly as the session will — what broadcast needs, so
  /// that it copies the bytes another link has already rewritten (a folded
  /// Ctrl modifier, say) rather than the raw ones, whatever the install order.
  void add(Object key, OutputInterceptor intercept, {bool innermost = false}) {
    _adopt();
    _links.removeWhere((l) => l.key == key);
    _links.insert(innermost ? 0 : _links.length, _Link(key, intercept));
    _install();
  }

  /// Removes the interceptor registered under [key]. No-op when absent.
  void remove(Object key) {
    _adopt();
    if (!_links.any((l) => l.key == key)) return;
    _links.removeWhere((l) => l.key == key);
    _install();
  }

  /// Runs [action] with [key]'s interceptor disabled — for a feature that
  /// needs to push data through [Terminal.paste] (control-char sanitizing,
  /// bracketed paste) without its own link seeing the result and acting on it
  /// a second time.
  T without<T>(Object key, T Function() action) {
    _adopt();
    final index = _links.indexWhere((l) => l.key == key);
    if (index == -1) return action();
    final link = _links[index];
    link.enabled = false;
    try {
      return action();
    } finally {
      link.enabled = true;
    }
  }

  /// Detaches the chain, restoring the bare session handler.
  void dispose() {
    _adopt();
    _links.clear();
    _install();
  }

  /// Picks up an `onOutput` assignment made behind the chain's back — a bridge
  /// connecting, reconnecting, or nulling the slot on teardown — and treats it
  /// as the new base.
  void _adopt() {
    final live = terminal.onOutput;
    if (identical(live, _installed)) return;
    _base = live;
    _install();
  }

  void _install() {
    if (_base == null || _links.isEmpty) {
      _installed = _base;
      terminal.onOutput = _base;
      return;
    }
    void dispatch(String data) => _runFrom(_links.length - 1, data);
    _installed = dispatch;
    terminal.onOutput = dispatch;
  }

  void _runFrom(int index, String data) {
    var i = index;
    while (i >= 0 && !_links[i].enabled) {
      i--;
    }
    if (i < 0) {
      _base?.call(data);
      return;
    }
    _links[i].intercept(data, (out) => _runFrom(i - 1, out));
  }
}
