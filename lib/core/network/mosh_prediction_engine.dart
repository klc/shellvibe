import 'dart:convert';

import '../models/mosh_prediction_mode.dart';

/// One character the user typed, waiting to be confirmed by the server's echo.
class _Prediction {
  _Prediction(this.glyph, this.inputStateNum, this.queuedAt);

  final String glyph;
  final int inputStateNum;
  final DateTime queuedAt;
}

/// Decides what locally-typed text to show before the server has echoed it.
///
/// Mosh's whole value proposition on a high-latency link is that keystrokes
/// appear immediately instead of waiting a round trip. This class owns only
/// that decision — what glyph to draw at the cursor, and when to stop drawing
/// it — never how it is rendered or how bytes reach the wire. It is pure Dart
/// and holds no socket, so it can be driven by a unit test one keystroke and
/// one server packet at a time.
///
/// The engine tracks a single "epoch": a run of predictions that the server
/// has been echoing back correctly. The instant a prediction turns out to be
/// wrong — a mismatched character, an unexpected control sequence, a stale
/// prediction that never got echoed — the whole epoch is thrown away and
/// nothing is shown again until a fresh prediction is confirmed from scratch.
/// This mirrors mosh's own predictor: partial trust is not on offer, because
/// a partially-wrong prediction is worse than none (the cursor position it
/// implies is simply false).
class MoshPredictionEngine {
  /// [adaptiveRttThreshold] is the RTT below which prediction is skipped in
  /// [MoshPredictionMode.adaptive] — under it, the server's own echo is
  /// already about as fast as showing a prediction would be.
  ///
  /// [minTimeout] is the floor under `2 * srtt` used by the staleness check
  /// (rule R5), so a prediction is never allowed to loiter indefinitely when
  /// RTT is null or tiny.
  ///
  /// [clock] is injected so tests can control the passage of time without a
  /// real `Timer`; it defaults to [DateTime.now].
  MoshPredictionEngine({
    MoshPredictionMode mode = MoshPredictionMode.adaptive,
    this.adaptiveRttThreshold = const Duration(milliseconds: 60),
    this.minTimeout = const Duration(milliseconds: 500),
    DateTime Function()? clock,
    // An initializing formal would have to be named `this._mode`, which no
    // caller outside this library could pass; the public name is `mode`.
    // ignore: prefer_initializing_formals
  }) : _mode = mode,
       _clock = clock ?? DateTime.now {
    _serverOutputDecoder = _newServerOutputDecoder();
  }

  /// When prediction is allowed to record and show anything. Switching to
  /// [MoshPredictionMode.never] drops all state immediately — there is no
  /// point holding predictions nobody will ever see.
  MoshPredictionMode get mode => _mode;
  set mode(MoshPredictionMode value) {
    _mode = value;
    if (value == MoshPredictionMode.never) {
      _killEpoch();
    }
  }

  MoshPredictionMode _mode;

  final Duration adaptiveRttThreshold;
  final Duration minTimeout;
  final DateTime Function() _clock;
  late ByteConversionSink _serverOutputDecoder;

  final List<_Prediction> _pending = [];
  bool _epochConfirmed = false;
  int? _deferredEchoAck;
  Duration? _lastRtt;

  /// The text that should currently be drawn at the cursor. Empty when
  /// nothing may be shown — either because nothing is confirmed yet (rule
  /// R3), because the RTT does not warrant it in adaptive mode, or because
  /// everything pending has just timed out.
  String get visibleText {
    _dropStale();
    if (!_epochConfirmed) return '';
    if (_mode == MoshPredictionMode.adaptive) {
      final rtt = _lastRtt;
      if (rtt == null || rtt < adaptiveRttThreshold) return '';
    }
    return _pending.map((p) => p.glyph).join();
  }

  /// Number of predictions currently held, shown or not. Exposed for tests
  /// and diagnostics rather than for any display decision.
  int get pendingCount {
    _dropStale();
    return _pending.length;
  }

  /// True once a byte from the server has matched the oldest pending
  /// prediction, byte-for-byte, in the current epoch. See [visibleText] for
  /// why this gate exists.
  bool get isEpochConfirmed {
    _dropStale();
    return _epochConfirmed;
  }

  /// Records a piece of user input exactly as it left the terminal, tagged
  /// with the input state number [MoshSession.send] returned for it — that
  /// number is what later ties an [onEchoAck] back to this prediction.
  ///
  /// Implements rule R1's classification: a single printable character is
  /// predicted, a single backspace retracts the most recent prediction (or
  /// kills the epoch if there is nothing to retract), and anything else —
  /// empty input, multi-character paste or IME batches, Enter, Tab, escape
  /// sequences, any other control character — kills the epoch outright,
  /// because none of those map onto "one more glyph at the cursor".
  void recordInput(String data, int inputStateNum) {
    if (_mode == MoshPredictionMode.never) return;
    if (data.length != 1) {
      _killEpoch();
      return;
    }
    final unit = data.codeUnitAt(0);
    if (unit == 0x08 || unit == 0x7F) {
      if (_pending.isNotEmpty) {
        _pending.removeLast();
      } else {
        // Nothing pending to retract, and we cannot know what the shell
        // itself is about to delete — trusting a guess here is exactly the
        // kind of false cursor position the epoch model exists to avoid.
        _killEpoch();
      }
      return;
    }
    if (unit >= 0x20) {
      _pending.add(_Prediction(data, inputStateNum, _clock()));
      return;
    }
    _killEpoch();
  }

  /// Retires every pending prediction whose input state number is at most
  /// [ackNum] — the server has echoed (or otherwise processed) up through
  /// that point, so those predictions no longer need to stand in for
  /// anything. An ack never confirms the epoch (rule R3): it says the server
  /// has moved on, not that it echoed the predicted glyph.
  ///
  /// Deferred while the epoch is unconfirmed, and that is load-bearing rather
  /// than an optimisation. A mosh host message carries the echoed bytes and
  /// the ack together, so an ack applied first would retire the very prediction
  /// the bytes are about to confirm. Keeping the greatest deferred ack means
  /// the byte match always gets its chance, whichever order the two stream
  /// listeners happen to deliver.
  void onEchoAck(int ackNum) {
    if (!_epochConfirmed) {
      if (_pending.isEmpty) return;
      if (_deferredEchoAck == null || ackNum > _deferredEchoAck!) {
        _deferredEchoAck = ackNum;
      }
      return;
    }
    _retireThroughAck(ackNum);
  }

  /// Feeds raw bytes received from the server through the confirmation
  /// state machine (rule R4).
  ///
  /// The bytes are decoded permissively — a screen update can arrive split
  /// across datagrams — and then walked character by character against the
  /// front of the pending queue. Any control character anywhere in the batch
  /// means something structural happened (cursor move, clear, bell) and the
  /// engine can no longer reason about where predictions sit on screen, so
  /// the whole epoch is killed rather than trusting a possibly-stale
  /// position. Only a clean run of printable characters can confirm
  /// anything, and the first mismatch in that run kills the epoch too.
  void onServerOutput(List<int> bytes) {
    _serverOutputDecoder.add(bytes);
  }

  void _consumeServerOutput(String text) {
    final units = text.codeUnits;
    for (final unit in units) {
      if (unit < 0x20 || unit == 0x7F) {
        _killEpoch();
        return;
      }
    }
    // Code-unit based, matching the classification recordInput uses to build
    // each prediction's single-code-unit glyph in the first place.
    for (final unit in units) {
      if (_pending.isEmpty) {
        // No predictions to check against; ordinary output and not an error,
        // so just stop here rather than treating it as a mismatch.
        _applyDeferredAck();
        return;
      }
      if (_pending.first.glyph.codeUnitAt(0) == unit) {
        // The security-critical moment (R3): only a real, observed match
        // against server output may flip this to true.
        _epochConfirmed = true;
        _pending.removeAt(0);
      } else {
        _killEpoch();
        return;
      }
    }
    _applyDeferredAck();
  }

  /// Records the latest smoothed RTT sample, used by [visibleText]'s
  /// adaptive-mode gate and by the staleness check in rule R5.
  void updateRtt(Duration? srtt) {
    _lastRtt = srtt;
  }

  /// Drops every prediction and confirmation state. Used on resize, rehome,
  /// and reconnect — none of those preserve any assumption a prediction was
  /// built on (cursor position, screen contents, even which server this is).
  void reset() {
    _pending.clear();
    _epochConfirmed = false;
    _deferredEchoAck = null;
    _lastRtt = null;
    // Do not let an incomplete UTF-8 sequence from the previous terminal
    // epoch leak into the next one. The old sink is intentionally abandoned:
    // closing it would flush a malformed replacement character into the state
    // machine during reset.
    _serverOutputDecoder = _newServerOutputDecoder();
  }

  /// Rule R5: a prediction older than `max(2 * srtt, minTimeout)` has almost
  /// certainly been lost or the server never intended to echo it (a password
  /// prompt, for instance) — either way the position it implies can no
  /// longer be trusted. Evaluated lazily on every read instead of via a
  /// `Timer` so the engine stays synchronous and deterministic under test.
  void _dropStale() {
    if (_pending.isEmpty) return;
    final srtt = _lastRtt;
    final threshold = srtt == null
        ? minTimeout
        : (srtt * 2 > minTimeout ? srtt * 2 : minTimeout);
    final now = _clock();
    final hadStale = _pending.any(
      (p) => now.difference(p.queuedAt) > threshold,
    );
    if (hadStale) {
      _killEpoch();
    }
  }

  void _killEpoch() {
    _pending.clear();
    _epochConfirmed = false;
    _deferredEchoAck = null;
  }

  void _applyDeferredAck() {
    final ackNum = _deferredEchoAck;
    _deferredEchoAck = null;
    if (ackNum != null && _epochConfirmed) {
      _retireThroughAck(ackNum);
    }
  }

  void _retireThroughAck(int ackNum) {
    _pending.removeWhere((p) => p.inputStateNum <= ackNum);
  }

  ByteConversionSink _newServerOutputDecoder() {
    return const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(_ServerOutputSink(_consumeServerOutput));
  }
}

final class _ServerOutputSink implements Sink<String> {
  const _ServerOutputSink(this._onChunk);

  final void Function(String) _onChunk;

  @override
  void add(String chunk) => _onChunk(chunk);

  @override
  void close() {}
}
