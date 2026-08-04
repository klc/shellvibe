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

  StreamSubscription<String>? _outputSubscription;
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
    _outputSubscription = pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
      (String data) {
        if (_isDisposed) return;
        terminal.write(data);
      },
      onError: (Object error) {
        if (_isDisposed) return;
        terminal.write('\r\n[PTY stream error: $error]\r\n');
      },
      onDone: _onStreamDone,
    );

    // 3. Wire window resize event from xterm Terminal -> Local PTY resize
    // Note: flutter_pty resize takes (rows, cols)
    terminal.onResize = (int width, int height, int pixelWidth, int pixelHeight) {
      resizeTerminal(width, height);
    };
  }

  Future<void> _onStreamDone() async {
    if (_isDisposed) return;
    try {
      // Note: `Pty.exitCode` is a `Future<int>`, so it must be awaited before
      // interpolating the value into the message.
      final code = await pty.exitCode;
      if (_isDisposed) return;
      terminal.write('\r\n\x1b[1;33m[Process exited with code $code]\x1b[0m\r\n');
    } catch (_) {
      if (_isDisposed) return;
      terminal.write('\r\n\x1b[1;33m[Session closed / Process exited]\x1b[0m\r\n');
    }
    dispose();
  }

  /// Resizes local PTY dimensions to [height] rows and [width] columns.
  void resizeTerminal(int width, int height) {
    if (_isDisposed) return;
    try {
      pty.resize(height, width);
    } catch (e) {
      terminal.write('\r\n\x1b[33m[PTY resize error: $e]\x1b[0m\r\n');
    }
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
    // Start the shell as a login shell (non-Windows) so it reads the user's
    // profile (.zprofile/.bash_profile) and restores their real PATH. A bare
    // shell inherits the GUI app's minimal launchd PATH, hiding Homebrew
    // binaries such as `htop`. Respect explicit caller arguments over this.
    final loginArgs = arguments.isEmpty && !Platform.isWindows;
    final env = <String, String>{
      ...Platform.environment,
      'TERM': 'xterm-256color',
      ...?environment,
    };
    final workDir = workingDirectory ?? Platform.environment['HOME'];

    Pty spawn(List<String> args) => Pty.start(
          exec,
          arguments: args,
          workingDirectory: workDir,
          environment: env,
          rows: rows,
          columns: columns,
        );

    if (!loginArgs) return spawn(arguments);
    try {
      return spawn(const ['-l']);
    } catch (_) {
      // `SHELL` may point at a shell that rejects `-l` (nushell, some
      // restricted shells). A terminal that opens with a thin PATH beats one
      // that refuses to open at all, so fall back to a bare invocation.
      return spawn(const []);
    }
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
