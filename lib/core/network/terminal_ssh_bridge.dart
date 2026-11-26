import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm3/xterm.dart';

import 'coalescing_terminal_writer.dart';

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

  /// Remote output reaches the terminal through a paced writer rather than
  /// going straight to [Terminal.write].
  ///
  /// A fast link delivers output faster than the terminal can parse it —
  /// `cat` of a large file, a verbose build, anything that scrolls hard.
  /// Writing each chunk as it lands holds the UI isolate, and where the
  /// chunks are small it floods the event loop instead, which looks the same
  /// from outside: a window that stops drawing. Chunks are gathered by frame
  /// and the batch is then paced, trading drain speed for a terminal that
  /// keeps drawing.
  ///
  /// stdout and stderr share one writer so their interleaving is preserved,
  /// and status messages go through it too — a direct [Terminal.write] would
  /// jump ahead of output still queued here.
  late final CoalescingTerminalWriter _writer =
      writerOverride ??
      CoalescingTerminalWriter(
        PacedTerminalWriter(terminal, waitForFrame: nextFrameOrTimeout),
      );

  /// Replaces the writer so a test can drive the write path without a frame
  /// pipeline.
  ///
  /// Both stages yield by awaiting the next frame, which never arrives under
  /// a plain unit test: the coalescer would hold every chunk forever and a
  /// burst past the pacer's budget would hang. Tests inject a stack with
  /// their own `waitForFrame`.
  @visibleForTesting
  final CoalescingTerminalWriter? writerOverride;

  bool _stdoutDone = false;
  bool _stderrDone = false;

  /// Returns true if the bridge has been disposed.
  bool get isDisposed => _isDisposed;

  TerminalSSHBridge({
    required this.terminal,
    required this.session,
    this.onClosed,
    this.writerOverride,
  }) {
    _bind();
  }

  void _bind() {
    // Wired here rather than at construction so an injected writer applies
    // backpressure exactly like the one this bridge builds for itself.
    _writer.onHandOff = _holdWhileBacklogged;

    // 1. Wire user input from xterm Terminal -> SSH session stdin
    void send(String data) {
      if (_isDisposed) return;
      try {
        session.write(Uint8List.fromList(utf8.encode(data)));
      } catch (e) {
        _writer.write('\r\n\x1b[33m[SSH write error: $e]\x1b[0m\r\n');
      }
    }

    terminal.onOutput = send;
    // Replies the terminal makes on its own (device attributes, cursor
    // position, focus reports) go straight to this session. Left to fall back
    // on onOutput they would pass through broadcast and reach every other
    // selected pane as if typed there.
    terminal.onReply = send;

    // 2. Wire remote output streams (stdout, stderr) from SSH session -> xterm Terminal
    _stdoutSubscription = session.stdout
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
      (String data) {
        if (_isDisposed) return;
        _writer.write(data);
      },
      onError: (Object error) {
        if (_isDisposed) return;
        _writer.write('\r\n[SSH stdout error: $error]\r\n');
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
        _writer.write(data);
      },
      onError: (Object error) {
        if (_isDisposed) return;
        _writer.write('\r\n[SSH stderr error: $error]\r\n');
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

  /// How many chunks the paced writer may hold before stdout is paused, as
  /// for the local PTY.
  static const maxPendingChunks = 2;

  /// stdout is paused until the backlog is back under [maxPendingChunks].
  bool _stdoutHeld = false;

  /// Stops reading while the paced writer has a backlog.
  ///
  /// The paced writer queues without limit, so a remote faster than the
  /// terminal (`cat` of a large file, `yes`) grew that queue for as long as
  /// it ran. Pausing stdout pauses the SSH channel under it, and dartssh2
  /// sends no window adjust while its channel is paused, so the remote stops
  /// once it has spent the window it holds. stderr shares that channel and
  /// stops with it.
  void _holdWhileBacklogged() {
    if (_isDisposed || _stdoutHeld) return;
    if (_writer.pendingChunks <= maxPendingChunks) return;
    _stdoutHeld = true;
    _stdoutSubscription?.pause();
    unawaited(_resumeWhenDrained());
  }

  Future<void> _resumeWhenDrained() async {
    while (!_isDisposed && _writer.pendingChunks > maxPendingChunks) {
      await _writer.nextFrame();
    }
    _stdoutHeld = false;
    if (!_isDisposed) _stdoutSubscription?.resume();
  }

  void _checkStreamsDone() {
    if (_isDisposed) return;
    if (_stdoutDone && _stderrDone) {
      _writer.write('\r\n\x1b[1;33m[Session closed / Process exited]\x1b[0m\r\n');
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
      _writer.write('\r\n\x1b[33m[SSH resize error: $e]\x1b[0m\r\n');
    }
  }

  /// Cancels stdout/stderr subscriptions, detaches terminal callbacks,
  /// and optionally closes the underlying SSH session.
  ///
  /// [discardOutput] drops output still queued instead of parsing it: for a
  /// terminal that is being thrown away, where parsing a large backlog only
  /// holds the UI.
  Future<void> dispose({
    bool closeSession = true,
    bool discardOutput = false,
  }) async {
    if (_isDisposed) return;
    _isDisposed = true;

    terminal.onOutput = null;
    terminal.onReply = null;
    terminal.onResize = null;

    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;

    await _stderrSubscription?.cancel();
    _stderrSubscription = null;

    // A terminal that stays on screen must not lose output the remote already
    // sent, so what is queued is drained before the writer goes.
    if (!discardOutput) _writer.flush();
    _writer.dispose();

    if (closeSession) {
      try {
        session.close();
      } catch (_) {}
    }
  }
}
