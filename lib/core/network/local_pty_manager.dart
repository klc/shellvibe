import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xterm3/xterm.dart';

import '../perf/write_path_metrics.dart';
import 'coalescing_terminal_writer.dart';
import 'pty_session.dart';

/// Two-way stream bridge binding an xterm [Terminal] UI widget
/// and a local pseudo-terminal [Pty] instance.
class TerminalLocalPtyBridge {
  final Terminal terminal;

  /// The shell process, read on its own isolate.
  final PtySession session;

  /// Receives a copy of each raw PTY output chunk before UTF-8 decoding.
  ///
  /// Device Link uses this tap to forward exact PTY bytes without disturbing
  /// the terminal's existing decoder and output chain.
  void Function(Uint8List bytes)? outputTap;

  /// Called once when the process behind this bridge has exited and the bridge
  /// is about to tear itself down.
  ///
  /// Anything sharing this session needs to hear about it: a Device Link phone
  /// is attached to a process that no longer exists, and nothing else on the
  /// desktop is going to notice on its behalf.
  void Function()? onExit;

  StreamSubscription<String>? _outputSubscription;
  bool _isDisposed = false;

  /// Output reaches the terminal batched by frame and then paced, rather than
  /// going straight to [Terminal.write].
  ///
  /// A local PTY hands over data as fast as the process can produce it, which
  /// is far faster than the terminal can parse it, and `flutter_pty` hands it
  /// over 1024 bytes at a time — one Dart port message per read. Writing each
  /// one as it lands is what put macOS's spinning wait cursor up during a
  /// benchmark: not a blocked isolate but a flooded one, an event loop that
  /// never empties long enough for a frame to run.
  ///
  /// [CoalescingTerminalWriter] gathers a frame's worth of those reads into
  /// one write; [PacedTerminalWriter] then bounds how long parsing the result
  /// may hold the isolate. The trade is real and deliberate: output drains
  /// slower in exchange for the app staying responsive.
  ///
  /// Every write in this bridge goes through it, status messages included —
  /// a direct [Terminal.write] would jump ahead of output still queued here
  /// and surface out of order.
  late final CoalescingTerminalWriter _writer =
      writerOverride ??
      CoalescingTerminalWriter(
        PacedTerminalWriter(terminal),
        onHandOff: _acknowledgeBatch,
      );


  /// Replaces the write stack so a test can drive it without a frame pipeline.
  ///
  /// Both stages hand over on the next frame, which never arrives under a
  /// plain unit test: the coalescer would hold every chunk forever. Tests
  /// inject a stack with their own `waitForFrame`.
  @visibleForTesting
  final CoalescingTerminalWriter? writerOverride;

  /// Returns true if the bridge has been disposed.
  bool get isDisposed => _isDisposed;

  TerminalLocalPtyBridge({
    required this.terminal,
    required this.session,
    this.outputTap,
    this.onExit,
    this.writerOverride,
  }) {
    _bind();
  }

  void _bind() {
    // Wired here rather than at construction so an injected writer is
    // acknowledged exactly like the one this bridge builds for itself.
    _writer.onHandOff = _acknowledgeBatch;

    // 1. Wire user input from xterm Terminal -> Local PTY stdin
    terminal.onOutput = (String data) {
      if (_isDisposed) return;
      try {
        session.write(Uint8List.fromList(utf8.encode(data)));
      } catch (e) {
        _writer.write('\r\n\x1b[33m[PTY write error: $e]\x1b[0m\r\n');
      }
    };

    // 2. Wire local PTY output stream -> xterm Terminal
    _outputSubscription = session.output
        .cast<List<int>>()
        .map<List<int>>((bytes) {
          final rawBytes = Uint8List.fromList(bytes);
          try {
            outputTap?.call(rawBytes);
          } catch (_) {
            // A diagnostic/transport tap must never break local terminal
            // rendering when its consumer is unavailable.
          }
          return rawBytes;
        })
        .transform<String>(const Utf8Decoder(allowMalformed: true))
        .listen(
          (String data) {
            if (_isDisposed) return;
            // Read both stages before the chunk joins them: what the
            // coalescer is holding says whether batching is engaging, and
            // what the pacer has queued says whether it has anything to pace.
            if (isWritePathInstrumented) {
              writePathMetrics.recordChunk(
                chars: data.length,
                pendingChunks: _writer.pendingChunks,
                bufferedChars: _writer.bufferedChars,
              );
            }
            _unacknowledgedBatches++;
            _writer.write(data);
          },
          onError: (Object error) {
            if (_isDisposed) return;
            _writer.write('\r\n[PTY stream error: $error]\r\n');
          },
          onDone: _onStreamDone,
        );

    // 3. Wire window resize event from xterm Terminal -> Local PTY resize
    // Note: flutter_pty resize takes (rows, cols)
    terminal.onResize =
        (int width, int height, int pixelWidth, int pixelHeight) {
          resizeTerminal(width, height);
        };
  }

  /// Batches taken from the reader that have not been reported back yet.
  ///
  /// One hand-over is not one batch: everything that arrives between two
  /// frames is merged into a single write, so acknowledging once per hand-over
  /// returns one credit for however many batches it covered. The reader's
  /// window then drains to nothing and the PTY is never read again — output
  /// stops, with no freeze to show for it.
  int _unacknowledgedBatches = 0;

  /// Reports the parsed batches, which is what lets the reader ask the PTY for
  /// more.
  ///
  /// The credit window lives on the reading isolate: it stops acknowledging
  /// the PTY once enough batches are in flight unreported, which fills the
  /// kernel's buffer and blocks the process writing into it. Acknowledging per
  /// batch rather than per read is the whole point — macOS hands over at most
  /// 1024 bytes per read, so a per-read acknowledgement would cost a round
  /// trip per KiB and cap throughput near 3 MB/s.
  void _acknowledgeBatch() {
    if (_isDisposed) return;
    while (_unacknowledgedBatches > 0) {
      _unacknowledgedBatches--;
      session.acknowledge();
    }
  }

  Future<void> _onStreamDone() async {
    if (_isDisposed) return;
    try {
      // Note: `Pty.exitCode` is a `Future<int>`, so it must be awaited before
      // interpolating the value into the message.
      final code = await session.exitCode;
      if (_isDisposed) return;
      _writer.write(
        '\r\n\x1b[1;33m[Process exited with code $code]\x1b[0m\r\n',
      );
    } catch (_) {
      if (_isDisposed) return;
      _writer.write(
        '\r\n\x1b[1;33m[Session closed / Process exited]\x1b[0m\r\n',
      );
    }
    final exited = onExit;
    dispose();
    exited?.call();
  }

  /// Resizes local PTY dimensions to [height] rows and [width] columns.
  void resizeTerminal(int width, int height) {
    if (_isDisposed) return;
    try {
      session.resize(height, width);
    } catch (e) {
      _writer.write('\r\n\x1b[33m[PTY resize error: $e]\x1b[0m\r\n');
    }
  }

  /// Cancels PTY output subscription, detaches terminal callbacks,
  /// and optionally kills the PTY process.
  Future<void> dispose({bool killPty = true}) async {
    if (_isDisposed) return;
    _isDisposed = true;

    terminal.onOutput = null;
    terminal.onResize = null;
    outputTap = null;
    onExit = null;

    await _outputSubscription?.cancel();
    _outputSubscription = null;

    // Teardown must not swallow output the process already produced, so drain
    // what is queued before dropping the writer.
    _writer
      ..flush()
      ..dispose();

    await session.dispose(kill: killPty);
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

  /// Starts a local shell on its own reading isolate.
  ///
  /// Throws [UnsupportedError] on iOS.
  Future<PtySession> startSession({
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
    final env = <String, String>{
      ...Platform.environment,
      'TERM': 'xterm-256color',
      // Launched from Finder the app inherits launchd's env, which lacks
      // COLORTERM. Programs that gate 24-bit output on it (oh-my-posh, delta,
      // bat) would silently fall back to the 256-colour cube.
      'COLORTERM': 'truecolor',
      ...?environment,
    };
    final workDir = workingDirectory ?? Platform.environment['HOME'];

    return PtyIsolateSession.start(
      PtySessionConfig(
        executable: exec,
        arguments: arguments.isEmpty ? defaultShellArguments(exec) : arguments,
        workingDirectory: workDir,
        environment: env,
        rows: rows,
        columns: columns,
      ),
    );
  }

  /// POSIX shells known to take `-l` for "login shell". Anything outside this
  /// set is started bare.
  static const Set<String> _loginFlagShells = {
    'sh',
    'bash',
    'zsh',
    'ksh',
    'ksh93',
    'mksh',
    'dash',
    'ash',
    'fish',
    'csh',
    'tcsh',
  };

  /// Arguments to start [executable] with when the caller gave none.
  ///
  /// Known POSIX shells are started as login shells so they read the user's
  /// profile (`.zprofile`/`.bash_profile`) and restore their real PATH — a
  /// bare shell inherits the GUI app's minimal launchd PATH, which hides
  /// Homebrew binaries such as `htop`.
  ///
  /// The flag is gated on a known-shell list rather than tried and retried:
  /// `Pty.start` forks and execs, so a shell that rejects `-l` still spawns
  /// successfully and then dies in the child with a usage error. There is no
  /// exception to catch, so an unrecognised shell (nushell, a restricted or
  /// wrapper shell) gets a bare invocation and a thin PATH — which beats a
  /// pane that opens onto a dead process.
  List<String> defaultShellArguments(String executable) {
    if (Platform.isWindows) return const [];
    final name = executable.split('/').last;
    return _loginFlagShells.contains(name) ? const ['-l'] : const [];
  }

  /// Spawns a local PTY process and binds it to [terminal].
  /// If run on iOS, writes a user-friendly notice to [terminal] and returns null.
  Future<TerminalLocalPtyBridge?> startAndBridge(
    Terminal terminal, {
    String? executable,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 24,
    int columns = 80,
    void Function(Uint8List bytes)? outputTap,
  }) async {
    if (!isSupportedPlatform) {
      terminal.write(
        '\r\n\x1b[1;31m[iOS Sandbox Restriction]\x1b[0m '
        'Local shell execution is disabled by Apple iOS app sandbox policy.\r\n'
        'Please connect to a remote host via SSH or Mosh.\r\n',
      );
      return null;
    }

    try {
      final session = await startSession(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        rows: rows,
        columns: columns,
      );

      return TerminalLocalPtyBridge(
        terminal: terminal,
        session: session,
        outputTap: outputTap,
      );
    } catch (e) {
      terminal.write('\r\n[PTY execution error: $e]\r\n');
      return null;
    }
  }
}
