import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm3/xterm.dart';

/// Two-way stream bridge binding an xterm [Terminal] UI widget
/// and a `dartssh2` [SSHSession] network stream.
class TerminalSSHBridge {
  final Terminal terminal;
  final SSHSession session;

  /// Invoked when both remote streams have ended and the session is being
  /// torn down — the remote shell exited or the connection dropped. Lets the
  /// owner (tab notifier) flip its connection state before the bridge
  /// detaches the terminal handlers.
  final void Function()? onClosed;

  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  bool _isDisposed = false;
  bool _stdoutDone = false;
  bool _stderrDone = false;

  /// Returns true if the bridge has been disposed.
  bool get isDisposed => _isDisposed;

  TerminalSSHBridge({
    required this.terminal,
    required this.session,
    this.onClosed,
  }) {
    _bind();
  }

  void _bind() {
    // 1. Wire user input from xterm Terminal -> SSH session stdin
    terminal.onOutput = (String data) {
      if (_isDisposed) return;
      try {
        session.write(Uint8List.fromList(utf8.encode(data)));
      } catch (e) {
        terminal.write('\r\n\x1b[33m[SSH write error: $e]\x1b[0m\r\n');
      }
    };

    // 2. Wire remote output streams (stdout, stderr) from SSH session -> xterm Terminal
    _stdoutSubscription = session.stdout
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
      (String data) {
        if (_isDisposed) return;
        terminal.write(data);
      },
      onError: (Object error) {
        if (_isDisposed) return;
        terminal.write('\r\n[SSH stdout error: $error]\r\n');
      },
      onDone: () {
        _stdoutDone = true;
        _checkStreamsDone();
      },
    );

    _stderrSubscription = session.stderr
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
      (String data) {
        if (_isDisposed) return;
        terminal.write(data);
      },
      onError: (Object error) {
        if (_isDisposed) return;
        terminal.write('\r\n[SSH stderr error: $error]\r\n');
      },
      onDone: () {
        _stderrDone = true;
        _checkStreamsDone();
      },
    );

    // 3. Wire window resize event from xterm Terminal -> SSH session terminal resize
    terminal.onResize = (int width, int height, int pixelWidth, int pixelHeight) {
      resizeTerminal(width, height, pixelWidth, pixelHeight);
    };
  }

  void _checkStreamsDone() {
    if (_isDisposed) return;
    if (_stdoutDone && _stderrDone) {
      terminal.write('\r\n\x1b[1;33m[Session closed / Process exited]\x1b[0m\r\n');
      onClosed?.call();
      dispose();
    }
  }

  /// Resizes the remote SSH session terminal dimensions to [width] columns and [height] rows.
  void resizeTerminal(int width, int height, [int pixelWidth = 0, int pixelHeight = 0]) {
    if (_isDisposed) return;
    try {
      session.resizeTerminal(width, height, pixelWidth, pixelHeight);
    } catch (e) {
      terminal.write('\r\n\x1b[33m[SSH resize error: $e]\x1b[0m\r\n');
    }
  }

  /// Cancels stdout/stderr subscriptions, detaches terminal callbacks,
  /// and optionally closes the underlying SSH session.
  Future<void> dispose({bool closeSession = true}) async {
    if (_isDisposed) return;
    _isDisposed = true;

    terminal.onOutput = null;
    terminal.onResize = null;

    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;

    await _stderrSubscription?.cancel();
    _stderrSubscription = null;

    if (closeSession) {
      try {
        session.close();
      } catch (_) {}
    }
  }
}
