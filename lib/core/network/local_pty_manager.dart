import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm2/xterm.dart';

/// Two-way stream bridge binding an xterm [Terminal] UI widget
/// and a local pseudo-terminal [Pty] instance.
class TerminalLocalPtyBridge {
  final Terminal terminal;
  final Pty pty;

  StreamSubscription<Uint8List>? _outputSubscription;
  bool _isDisposed = false;

  /// Returns true if the bridge has been disposed.
  bool get isDisposed => _isDisposed;

  TerminalLocalPtyBridge({
    required this.terminal,
    required this.pty,
  }) {
    _bind();
  }

  void _bind() {
    // 1. Wire user input from xterm Terminal -> Local PTY stdin
    terminal.onOutput = (String data) {
      if (_isDisposed) return;
      try {
        pty.write(Uint8List.fromList(utf8.encode(data)));
      } catch (e) {
        terminal.write('\r\n\x1b[33m[PTY write error: $e]\x1b[0m\r\n');
      }
    };

    // 2. Wire local PTY output stream -> xterm Terminal
    _outputSubscription = pty.output.listen(
      (Uint8List data) {
        if (_isDisposed) return;
        terminal.write(utf8.decode(data, allowMalformed: true));
      },
      onError: (Object error) {
        if (_isDisposed) return;
        terminal.write('\r\n[PTY stream error: $error]\r\n');
      },
    );

    // 3. Wire window resize event from xterm Terminal -> Local PTY resize
    // Note: flutter_pty resize takes (rows, cols)
    terminal.onResize = (int width, int height, int pixelWidth, int pixelHeight) {
      if (_isDisposed) return;
      try {
        pty.resize(height, width);
      } catch (e) {
        terminal.write('\r\n\x1b[33m[PTY resize error: $e]\x1b[0m\r\n');
      }
    };
  }

  /// Cancels PTY output subscription, detaches terminal callbacks,
  /// and optionally kills the PTY process.
  Future<void> dispose({bool killPty = true}) async {
    if (_isDisposed) return;
    _isDisposed = true;

    terminal.onOutput = null;
    terminal.onResize = null;

    await _outputSubscription?.cancel();
    _outputSubscription = null;

    if (killPty) {
      try {
        pty.kill();
      } catch (_) {}
    }
  }
}

/// Manages local shell process creation using `flutter_pty` across platforms
/// (macOS, Windows, Linux, Android) with iOS sandbox restriction handling.
class LocalPtyManager {
  /// Returns true if the current operating system supports spawning local PTY processes.
  /// Returns false on iOS due to Apple App Sandbox policies.
  bool get isSupportedPlatform => !Platform.isIOS;

  /// Returns the default system shell executable path for the current OS.
  String getDefaultShell() {
    if (Platform.isWindows) {
      return 'powershell.exe';
    } else if (Platform.isMacOS) {
      return Platform.environment['SHELL'] ?? '/bin/zsh';
    } else {
      return Platform.environment['SHELL'] ?? '/bin/bash';
    }
  }

  /// Spawns a local pseudo-terminal [Pty] process.
  /// Throws [UnsupportedError] on iOS.
  Pty startPty({
    String? executable,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 24,
    int columns = 80,
  }) {
    if (!isSupportedPlatform) {
      throw UnsupportedError(
        'Local shell execution is not supported on iOS due to Apple App Sandbox policy.',
      );
    }

    final exec = executable ?? getDefaultShell();

    return Pty.start(
      exec,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      rows: rows,
      columns: columns,
    );
  }

  /// Spawns a local PTY process and binds it to [terminal].
  /// If run on iOS, writes a user-friendly notice to [terminal] and returns null.
  TerminalLocalPtyBridge? startAndBridge(
    Terminal terminal, {
    String? executable,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 24,
    int columns = 80,
  }) {
    if (!isSupportedPlatform) {
      terminal.write(
        '\r\n\x1b[1;31m[iOS Sandbox Restriction]\x1b[0m '
        'Local shell execution is disabled by Apple iOS app sandbox policy.\r\n'
        'Please connect to a remote host via SSH or Mosh.\r\n',
      );
      return null;
    }

    try {
      final pty = startPty(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        rows: rows,
        columns: columns,
      );

      return TerminalLocalPtyBridge(terminal: terminal, pty: pty);
    } catch (e) {
      terminal.write('\r\n[PTY execution error: $e]\r\n');
      return null;
    }
  }
}
