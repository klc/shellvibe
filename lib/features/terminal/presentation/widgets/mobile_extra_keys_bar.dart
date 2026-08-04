import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm2/xterm.dart';

class MobileExtraKeysBar extends StatefulWidget {
  final Terminal? terminal;
  final void Function(String data)? onInput;

  const MobileExtraKeysBar({
    super.key,
    this.terminal,
    this.onInput,
  });

  @override
  State<MobileExtraKeysBar> createState() => _MobileExtraKeysBarState();
}

class _MobileExtraKeysBarState extends State<MobileExtraKeysBar> {
  bool _ctrlActive = false;
  bool _altActive = false;

  /// The `terminal.onOutput` handler set by the SSH/PTY bridge while this
  /// bar's interceptor is installed.
  void Function(String data)? _underlyingOnOutput;

  /// Stable reference to [_interceptOutput]. Method tear-offs are not
  /// guaranteed identical across accesses, so the install/restore guards must
  /// compare against this stored reference, not a fresh tear-off.
  late final void Function(String data) _intercept = _interceptOutput;

  /// Set in [dispose]. This bar does not own the `onOutput` slot exclusively —
  /// `BroadcastInputRouter` may have wrapped the interceptor after it was
  /// installed, in which case [dispose] cannot pull it back out of the chain.
  /// A detached interceptor must then behave as a pure pass-through rather
  /// than keep folding modifiers for a widget that is gone.
  bool _detached = false;

  /// Installs an `onOutput` interceptor so the sticky Ctrl/Alt modifiers also
  /// apply to characters typed on the real (IME/hardware) keyboard, not only
  /// to the bar's own keys. Idempotent — re-run it after a modifier toggle so
  /// it survives the bridge (re)assigning `onOutput` after a late connect.
  void _installOutputInterceptor() {
    final t = widget.terminal;
    if (t == null || identical(t.onOutput, _intercept)) return;
    _underlyingOnOutput = t.onOutput;
    t.onOutput = _intercept;
  }

  /// Passes output through, folding the sticky Ctrl/Alt modifier into the next
  /// single printable ASCII character. Terminal-generated sequences (resize
  /// replies, focus reports, ...) are multi-byte and pass through untouched.
  void _interceptOutput(String data) {
    final underlying = _underlyingOnOutput;
    if (_detached || (!_ctrlActive && !_altActive)) {
      underlying?.call(data);
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
        underlying?.call(output);
        if (mounted) {
          setState(() {
            _ctrlActive = false;
            _altActive = false;
          });
        }
        return;
      }
    }
    underlying?.call(data);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _installOutputInterceptor();
  }

  @override
  void dispose() {
    _detached = true;
    final t = widget.terminal;
    if (t != null && identical(t.onOutput, _intercept)) {
      t.onOutput = _underlyingOnOutput;
    }
    super.dispose();
  }

  void _sendData(String rawChar, {String? ctrlChar, String? escapeCode}) {
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
      widget.terminal!.onOutput?.call(output);
    }

    // Reset Android/iOS IME state after extra key press to prevent composition corruption
    try {
      SystemChannels.textInput.invokeMethod(
        'TextInput.setEditingState',
        const TextEditingValue(
          text: '  ',
          selection: TextSelection.collapsed(offset: 2),
        ).toJSON(),
      );
    } catch (_) {}

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
    final theme = Theme.of(context);
    Color backgroundColor = isModifier
        ? (isActive ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest)
        : theme.colorScheme.surface;
    Color textColor = isModifier
        ? (isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface)
        : theme.colorScheme.onSurface;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: Theme.of(context).colorScheme.surfaceContainer,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
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
            const VerticalDivider(width: 12),
            // Action & Character Keys
            _buildKeyButton(
              key: const Key('key_esc'),
              label: 'Esc',
              onTap: () => _sendData('Esc', ctrlChar: '\x1b', escapeCode: '\x1b'),
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
            const VerticalDivider(width: 12),
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
