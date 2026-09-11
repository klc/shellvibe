import 'package:flutter/material.dart';
import 'package:xterm3/xterm.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/services/terminal_output_chain.dart';

class MobileExtraKeysBar extends StatefulWidget {
  /// Layout height of the bar, exported so a pane that overlays the bar on the
  /// terminal can keep that much of the viewport clear.
  /// Fixed so the keyboard-stable terminal layout can reserve it up front.
  /// 56 = 8 padding + a 40px key + 8 padding, which is what a 44px-ish touch
  /// target needs once the key has a radius.
  static const double barHeight = 56;

  final Terminal? terminal;

  /// The pane's output chain. The bar registers its modifier interceptor here
  /// so it composes with broadcast in either install order and can always take
  /// itself back out. When omitted (tests, previews) the bar makes a private
  /// chain over [terminal].
  final TerminalOutputChain? outputChain;

  final void Function(String data)? onInput;

  /// Hands the terminal whatever the keyboard is still composing, called
  /// before every key this bar sends.
  ///
  /// A bar key bypasses the IME, but the word the user is in the middle of
  /// typing is still sitting in it — the terminal has not seen a byte of it.
  /// Send the key without flushing and it lands against a line that is missing
  /// that word, which is why `www` + Tab used to complete an empty line. The
  /// flush has to go through the terminal view
  /// ([TerminalViewState.commitComposing]) rather than a raw
  /// `TextInput.setEditingState` call: the raw call resets the platform buffer
  /// while leaving xterm's copy of it — and any open composing range —
  /// untouched, so every following delta is measured against a buffer that no
  /// longer exists, which breaks backspace and replays stale text.
  final VoidCallback? onFlushInput;

  const MobileExtraKeysBar({
    super.key,
    this.terminal,
    this.outputChain,
    this.onInput,
    this.onFlushInput,
  });

  @override
  State<MobileExtraKeysBar> createState() => _MobileExtraKeysBarState();
}

class _MobileExtraKeysBarState extends State<MobileExtraKeysBar> {
  bool _ctrlActive = false;
  bool _altActive = false;

  /// Chain key for this bar's interceptor.
  static const Object _chainKey = 'mobile_extra_keys';

  /// The chain the interceptor is registered in: the pane's own when one was
  /// handed down, otherwise a private one over [MobileExtraKeysBar.terminal]
  /// so the bar behaves the same when used standalone.
  TerminalOutputChain? _ownChain;

  TerminalOutputChain? get _chain {
    final provided = widget.outputChain;
    if (provided != null) return provided;
    final t = widget.terminal;
    if (t == null) return null;
    return _ownChain ??= TerminalOutputChain(t);
  }

  /// Registers the output interceptor so the sticky Ctrl/Alt modifiers also
  /// apply to characters typed on the real (IME/hardware) keyboard, not only
  /// to the bar's own keys. Idempotent — re-run it after a modifier toggle so
  /// it is picked up once a late connect gives the pane a session handler.
  void _installOutputInterceptor() {
    final chain = _chain;
    if (chain == null || chain.has(_chainKey)) return;
    chain.add(_chainKey, _interceptOutput);
  }

  /// Passes output down the chain, folding the sticky Ctrl/Alt modifier into
  /// the next single printable ASCII character. Terminal-generated sequences
  /// (resize replies, focus reports, ...) are multi-byte and pass through
  /// untouched.
  void _interceptOutput(String data, void Function(String) next) {
    if (!_ctrlActive && !_altActive) {
      next(data);
      return;
    }
    if (data.length == 1) {
      final code = data.codeUnitAt(0);
      if (code >= 32 && code <= 126) {
        var output = data;
        if (_ctrlActive) {
          // Ctrl + letter/symbol -> ASCII control code (A-Z/a-z -> 1-26).
          output = String.fromCharCode(code & 0x1F);
        }
        if (_altActive) {
          output = '\x1b$output';
        }
        next(output);
        if (mounted) {
          setState(() {
            _ctrlActive = false;
            _altActive = false;
          });
        }
        return;
      }
    }
    next(data);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _installOutputInterceptor();
  }

  @override
  void dispose() {
    // Removing by key works whatever else has since joined the chain, so the
    // bar never leaves a dead interceptor folding modifiers behind it.
    _chain?.remove(_chainKey);
    super.dispose();
  }

  void _sendData(String rawChar, {String? ctrlChar, String? escapeCode}) {
    // The IME may still be holding a half-typed word the terminal has never
    // seen. Commit it first so this key arrives after it, in the order the
    // user typed. The bar's own interceptor stays out of that text, so a
    // sticky modifier is spent on the bar key rather than on the flush.
    final chain = _chain;
    if (chain != null) {
      chain.without(_chainKey, () => widget.onFlushInput?.call());
    } else {
      widget.onFlushInput?.call();
    }

    String output = escapeCode ?? rawChar;

    if (_ctrlActive) {
      if (ctrlChar != null) {
        output = ctrlChar;
      } else if (rawChar.length == 1) {
        final code = rawChar.codeUnitAt(0);
        if (code >= 65 && code <= 90) {
          // A-Z -> ASCII 1-26
          output = String.fromCharCode(code - 64);
        } else if (code >= 97 && code <= 122) {
          // a-z -> ASCII 1-26
          output = String.fromCharCode(code - 96);
        } else {
          // Symbols ASCII control code conversion
          switch (rawChar) {
            case '|':
              output = '\x1c';
              break;
            case '~':
              output = '\x1e';
              break;
            case '/':
              output = '\x1f';
              break;
            case '-':
              output = '\x1f';
              break;
            case '[':
              output = '\x1b';
              break;
            case '\\':
              output = '\x1c';
              break;
            case ']':
              output = '\x1d';
              break;
            case '^':
              output = '\x1e';
              break;
            case '_':
              output = '\x1f';
              break;
            case '@':
              output = '\x00';
              break;
            default:
              if (code >= 32 && code <= 126) {
                output = String.fromCharCode(code & 0x1F);
              }
          }
        }
      }
    }

    if (_altActive) {
      output = '\x1b$output';
    }

    if (widget.onInput != null) {
      widget.onInput!(output);
    } else if (widget.terminal != null) {
      // The modifiers are already folded in above, so this must not run back
      // through this bar's own interceptor — but it does go through the rest
      // of the chain, so a bar keypress broadcasts like a typed one.
      chain?.without(_chainKey, () => widget.terminal!.onOutput?.call(output));
    }

    // Reset sticky keys after next keypress
    if (_ctrlActive || _altActive) {
      setState(() {
        _ctrlActive = false;
        _altActive = false;
      });
    }
  }

  Widget _buildKeyButton({
    required Key key,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    bool isModifier = false,
  }) {
    final tokens = ShellVibeTokens.resolve(context);
    // A held modifier is the one state on this bar that must survive a glance
    // at a phone in daylight, so it gets the brand fill *and* a glow rather
    // than a colour swap alone.
    final Color background = isActive
        ? tokens.brand.withValues(alpha: 0.20)
        : Colors.transparent;
    final Color ring = isActive
        ? tokens.brand.withValues(alpha: 0.42)
        : tokens.textPrimary.withValues(alpha: 0.07);
    final Color foreground = isActive ? tokens.brandSoft : tokens.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 40,
          constraints: const BoxConstraints(minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ring),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: tokens.brand.withValues(alpha: 0.18),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: shellvibeMono(
              context,
              size: 12.5,
              weight: isModifier ? FontWeight.w600 : FontWeight.w400,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      height: MobileExtraKeysBar.barHeight,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tokens.surfaceRaised, tokens.surfaceLow],
        ),
        border: Border(
          top: BorderSide(color: tokens.textPrimary.withValues(alpha: 0.08)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Sticky Modifier: CTRL
            _buildKeyButton(
              key: const Key('key_ctrl'),
              label: 'Ctrl',
              isModifier: true,
              isActive: _ctrlActive,
              onTap: () {
                _installOutputInterceptor();
                setState(() => _ctrlActive = !_ctrlActive);
              },
            ),
            // Sticky Modifier: ALT
            _buildKeyButton(
              key: const Key('key_alt'),
              label: 'Alt',
              isModifier: true,
              isActive: _altActive,
              onTap: () {
                _installOutputInterceptor();
                setState(() => _altActive = !_altActive);
              },
            ),
            const SizedBox(width: 6),
            // Action & Character Keys
            _buildKeyButton(
              key: const Key('key_esc'),
              label: 'Esc',
              onTap: () =>
                  _sendData('Esc', ctrlChar: '\x1b', escapeCode: '\x1b'),
            ),
            _buildKeyButton(
              key: const Key('key_tab'),
              label: 'Tab',
              onTap: () => _sendData('Tab', ctrlChar: '\t', escapeCode: '\t'),
            ),
            _buildKeyButton(
              key: const Key('key_pipe'),
              label: '|',
              onTap: () => _sendData('|'),
            ),
            _buildKeyButton(
              key: const Key('key_tilde'),
              label: '~',
              onTap: () => _sendData('~'),
            ),
            _buildKeyButton(
              key: const Key('key_slash'),
              label: '/',
              onTap: () => _sendData('/'),
            ),
            _buildKeyButton(
              key: const Key('key_dash'),
              label: '-',
              onTap: () => _sendData('-'),
            ),
            const SizedBox(width: 6),
            // Navigation Arrow Keys
            _buildKeyButton(
              key: const Key('key_arrow_left'),
              label: '←',
              onTap: () => _sendData('left', escapeCode: '\x1b[D'),
            ),
            _buildKeyButton(
              key: const Key('key_arrow_up'),
              label: '↑',
              onTap: () => _sendData('up', escapeCode: '\x1b[A'),
            ),
            _buildKeyButton(
              key: const Key('key_arrow_down'),
              label: '↓',
              onTap: () => _sendData('down', escapeCode: '\x1b[B'),
            ),
            _buildKeyButton(
              key: const Key('key_arrow_right'),
              label: '→',
              onTap: () => _sendData('right', escapeCode: '\x1b[C'),
            ),
          ],
        ),
      ),
    );
  }
}
