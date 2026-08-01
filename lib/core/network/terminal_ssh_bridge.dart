import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm2/xterm.dart';

/// Two-way stream bridge binding an xterm [Terminal] UI widget
/// and a `dartssh2` [SSHSession] network stream.
class TerminalSSHBridge {
  final Terminal terminal;
  final SSHSession session;

  StreamSubscription<Uint8List>? _stdoutSubscription;
  StreamSubscription<Uint8List>? _stderrSubscription;
  bool _isDisposed = false;

  /// Returns true if the bridge has been disposed.
  bool get isDisposed => _isDisposed;

  TerminalSSHBridge({
    required this.terminal,
    required this.session,
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
    _stdoutSubscription = session.stdout.listen(
      (Uint8List data) {
        if (_isDisposed) return;
        terminal.write(utf8.decode(data, allowMalformed: true));
      },
      onError: (Object error) {
        if (_isDisposed) return;
        terminal.write('\r\n[SSH stdout error: $error]\r\n');
      },
    );

    _stderrSubscription = session.stderr.listen(
      (Uint8List data) {
        if (_isDisposed) return;
        terminal.write(utf8.decode(data, allowMalformed: true));
      },
      onError: (Object error) {
        if (_isDisposed) return;
        terminal.write('\r\n[SSH stderr error: $error]\r\n');
      },
    );

    // 3. Wire window resize event from xterm Terminal -> SSH session terminal resize
    terminal.onResize = (int width, int height, int pixelWidth, int pixelHeight) {
      if (_isDisposed) return;
      try {
        session.resizeTerminal(width, height, pixelWidth, pixelHeight);
      } catch (e) {
        terminal.write('\r\n\x1b[33m[SSH resize error: $e]\x1b[0m\r\n');
      }
    };
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
