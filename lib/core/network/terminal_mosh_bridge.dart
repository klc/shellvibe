import 'dart:async';
import 'dart:convert';

import 'package:xterm3/xterm.dart';

import 'mosh_session_manager.dart';

/// Two-way bridge between an xterm [Terminal] and a Mosh [MoshTransport].
///
/// The mirror of `TerminalSSHBridge`, down to the [dispose] signature, so the
/// tab layer can hold either one without special-casing. Only the carrier
/// differs — and with it the failure model: Mosh has a single output stream and
/// no stderr, and the session ends on [MoshTransport.done] rather than on both
/// streams draining.
class TerminalMoshBridge {
  final Terminal terminal;
  final MoshTransport session;

  /// Invoked when the remote side ended the session, before the bridge detaches
  /// the terminal handlers. Lets the owner flip its connection state first.
  final void Function()? onClosed;

  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<Object>? _errorsSubscription;
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  TerminalMoshBridge({
    required this.terminal,
    required this.session,
    this.onClosed,
  }) {
    _bind();
  }

  void _bind() {
    // 1. User input from xterm -> Mosh input queue.
    terminal.onOutput = (String data) {
      if (_isDisposed) return;
      try {
        session.send(utf8.encode(data));
      } catch (e) {
        terminal.write('\r\n\x1b[33m[Mosh write error: $e]\x1b[0m\r\n');
      }
    };

    // 2. Host output -> xterm. Decoded through the stream transformer rather
    // than per chunk: a screen diff can split a multi-byte sequence across
    // datagrams.
    _stdoutSubscription = session.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (String data) {
            if (_isDisposed) return;
            terminal.write(data);
          },
          onError: (Object error) {
            if (_isDisposed) return;
            terminal.write('\r\n[Mosh output error: $error]\r\n');
          },
        );

    // 3. Non-fatal transport errors (a dropped socket, a packet that would not
    // decrypt). Surfaced, never fatal — the session outlives them.
    _errorsSubscription = session.errors.listen((Object error) {
      if (_isDisposed) return;
      terminal.write('\r\n\x1b[33m[Mosh: $error]\x1b[0m\r\n');
    });

    // 4. Resize from xterm -> Mosh.
    terminal.onResize =
        (int width, int height, int pixelWidth, int pixelHeight) {
          resizeTerminal(width, height, pixelWidth, pixelHeight);
        };

    // 5. End of session. Silence never gets here: only a server shutdown or a
    // local close completes `done`.
    unawaited(session.done.then((_) => _handleDone()));
  }

  void _handleDone() {
    if (_isDisposed) return;
    terminal.write('\r\n\x1b[1;33m[Session closed / Process exited]\x1b[0m\r\n');
    onClosed?.call();
    unawaited(dispose());
  }

  /// Resizes the remote terminal to [width] columns and [height] rows. The
  /// pixel dimensions are accepted for signature parity with the SSH bridge;
  /// Mosh's resize instruction carries cells only.
  void resizeTerminal(
    int width,
    int height, [
    int pixelWidth = 0,
    int pixelHeight = 0,
  ]) {
    if (_isDisposed) return;
    try {
      session.resize(width, height);
    } catch (e) {
      terminal.write('\r\n\x1b[33m[Mosh resize error: $e]\x1b[0m\r\n');
    }
  }

  /// Cancels subscriptions, detaches terminal callbacks, and optionally closes
  /// the underlying Mosh session.
  Future<void> dispose({bool closeSession = true}) async {
    if (_isDisposed) return;
    _isDisposed = true;

    terminal.onOutput = null;
    terminal.onResize = null;

    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;

    await _errorsSubscription?.cancel();
    _errorsSubscription = null;

    if (closeSession) {
      try {
        await session.close();
      } catch (_) {}
    }
  }
}
