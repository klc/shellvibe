import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:xterm3/xterm.dart';

/// Batches terminal output into frame-sized writes before the paced writer
/// sees it.
///
/// [PacedTerminalWriter] bounds how long a *drain pass* may run, and yields
/// between the chunks it has queued. That only helps when a queue forms. On
/// the local PTY path one never does: `flutter_pty` reads the descriptor into
/// a 1024-byte stack buffer and posts every read as its own Dart port message,
/// so each chunk arrives as a separate event, is drained inside that event,
/// and leaves the queue empty again. Measured over a termbench run: 180,697
/// chunks, every one of them exactly 1024 characters, queue depth never above
/// zero, longest gap between arrivals 0.81ms.
///
/// The isolate was never blocked — it was drowning. termbench's payload is
/// some 5.6 million port messages, each costing an event, a microtask and a
/// [Terminal.write], and at roughly 83,000 of those a second the event loop
/// never empties long enough for a frame to run. Build stayed at 0.9ms and
/// raster at 2.6ms while 108 seconds produced 291 frames and one frame's
/// vsync-to-raster span reached 74.5 seconds.
///
/// So chunks accumulate here and are handed over on the next frame, which
/// collapses a frame's worth of events into one write.
///
/// **On its own that fixed nothing, and the measurement is worth keeping.**
/// Batching only removes [Terminal.write] calls, and the cost is already paid
/// before it: each port message costs an event, a `Uint8List` copy, the
/// output tap, a UTF-8 transform and a listener call. A termbench run with
/// batching in place still froze — 131 frames in 112.8 seconds against 291
/// without it — while the counters put the real scale at 3,083,644 chunks and
/// 27,332 a second. Raising the read size did not help either: xterm3's own
/// example app reads 16 KiB through `flutter_pty2`, writes each chunk
/// straight to the terminal, and freezes exactly the same way.
///
/// What separates a terminal that stays smooth is backpressure — not reading
/// faster than it can draw. This class carries the half of that which the
/// producer cannot do for itself: [onHandOff] tells a bridge holding a read
/// acknowledgement when the buffer has drained and the next read may come.
class CoalescingTerminalWriter {
  CoalescingTerminalWriter(
    this._writer, {
    this.maxWriteChars = 256 * 1024,
    this.onHandOff,
    Future<void> Function()? waitForFrame,
  }) : _waitForFrame = waitForFrame ?? _endOfFrame {
    if (maxWriteChars <= 0) {
      throw ArgumentError.value(
        maxWriteChars,
        'maxWriteChars',
        'must be positive',
      );
    }
  }

  final PacedTerminalWriter _writer;

  /// Largest batch handed over in one piece.
  ///
  /// A frame's accumulation is unbounded — a fast producer can deliver
  /// megabytes between two frames — and [PacedTerminalWriter] checks its
  /// budget *between* queued chunks, so one oversized chunk would be parsed
  /// atomically and cost exactly the stall this class exists to remove.
  /// Reaching the cap hands over immediately rather than waiting for the
  /// frame, which also means a flood queues several chunks at once and the
  /// pacer's budget finally has something to act on.
  final int maxWriteChars;

  /// Called after each batch reaches the paced writer.
  ///
  /// A producer that has to be told when the buffer drained — one holding a
  /// read acknowledgement back as backpressure — has no other way to know.
  ///
  /// Assignable rather than final so an owner can wire it onto a writer it
  /// did not construct. A bridge that took its writer from a test would
  /// otherwise silently skip the acknowledgement, and the test path would
  /// stop resembling the real one.
  void Function()? onHandOff;

  /// Injectable so the batching can be tested without a frame pipeline.
  final Future<void> Function() _waitForFrame;

  final StringBuffer _buffer = StringBuffer();

  var _flushScheduled = false;

  var _disposed = false;

  /// Characters accumulated but not yet handed to the paced writer.
  int get bufferedChars => _buffer.length;

  /// Chunks queued in the paced writer, not counting [bufferedChars].
  int get pendingChunks => _writer.pendingChunks;

  /// Whether anything is waiting to reach the terminal, at either stage.
  bool get hasPendingOutput => _buffer.isNotEmpty || _writer.hasPendingOutput;

  /// Queues [data] for the terminal.
  void write(String data) {
    if (_disposed || data.isEmpty) return;
    _buffer.write(data);
    if (_buffer.length >= maxWriteChars) {
      _handOff();
      return;
    }
    _scheduleHandOff();
  }

  /// Writes everything buffered, at both stages, without pacing.
  ///
  /// For the cases where latency beats smoothness — a prompt that has to
  /// appear now, or a teardown that has to leave nothing unparsed.
  void flush() {
    if (_disposed) return;
    _handOff();
    _writer.flush();
  }

  /// Drops anything not yet written and stops batching.
  void dispose() {
    _disposed = true;
    _buffer.clear();
    _writer.dispose();
  }

  void _handOff() {
    if (_buffer.isEmpty) return;
    final batch = _buffer.toString();
    _buffer.clear();
    // Ordering is preserved: the paced writer keeps its queue FIFO, and a
    // batch cut mid-escape-sequence is safe because the parser is a state
    // machine that carries across writes.
    _writer.write(batch);
    onHandOff?.call();
  }

  void _scheduleHandOff() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    unawaited(
      _waitForFrame().then((_) {
        _flushScheduled = false;
        if (!_disposed) _handOff();
      }),
    );
  }
}

/// Waiting on the end of a frame also schedules one when none is pending, so
/// a burst that arrives while the app is idle still reaches the terminal.
Future<void> _endOfFrame() => SchedulerBinding.instance.endOfFrame;
