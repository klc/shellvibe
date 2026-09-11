import 'dart:convert';

import 'frame_metrics.dart' show DurationStats, kPerfInstrumentationEnabled;

/// Marker for the write-path report line, kept separate from
/// [kPerfReportMarker] so a runner that only knows about frame timings does
/// not have to learn a new shape to keep working.
const String kWritePathReportMarker = '[shellvibe-write]';

/// Summary statistics for a quantity that is not a duration.
///
/// [DurationStats] renders everything as milliseconds, which is wrong for a
/// byte count and a queue depth. Same nearest-rank percentile, no unit.
class CountStats {
  const CountStats({
    required this.sampleCount,
    required this.mean,
    required this.p50,
    required this.p95,
    required this.p99,
    required this.max,
    required this.total,
  });

  /// Builds a summary from an *already sorted* ascending list.
  factory CountStats.fromSorted(List<int> sorted) {
    if (sorted.isEmpty) {
      return const CountStats(
        sampleCount: 0,
        mean: 0,
        p50: 0,
        p95: 0,
        p99: 0,
        max: 0,
        total: 0,
      );
    }
    var total = 0;
    for (final value in sorted) {
      total += value;
    }
    return CountStats(
      sampleCount: sorted.length,
      mean: total / sorted.length,
      p50: _percentile(sorted, 0.50),
      p95: _percentile(sorted, 0.95),
      p99: _percentile(sorted, 0.99),
      max: sorted.last,
      total: total,
    );
  }

  final int sampleCount;
  final double mean;
  final int p50;
  final int p95;
  final int p99;
  final int max;
  final int total;

  static int _percentile(List<int> sorted, double fraction) {
    final rank = (fraction * sorted.length).ceil();
    final index = (rank - 1).clamp(0, sorted.length - 1);
    return sorted[index];
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'samples': sampleCount,
    'mean': double.parse(mean.toStringAsFixed(1)),
    'p50': p50,
    'p95': p95,
    'p99': p99,
    'max': max,
    'total': total,
  };
}

/// One finished write-path measurement window.
class WritePathSnapshot {
  const WritePathSnapshot({
    required this.label,
    required this.wallClockMicros,
    required this.chunkChars,
    required this.pendingDepth,
    required this.bufferedChars,
    required this.arrivalGap,
    required this.totalChunks,
    required this.totalChars,
  });

  final String label;
  final int wallClockMicros;

  /// Decoded length of each chunk handed to the paced writer.
  final CountStats chunkChars;

  /// How many chunks were already queued in the *paced* writer when this one
  /// arrived.
  ///
  /// Read alone this is misleading once batching is in front of it: the
  /// coalescer hands over one batch per frame, the pacer drains it inside
  /// that turn, and the depth reads zero whether or not batching is working.
  /// [bufferedChars] is the series that says what the coalescer is holding.
  final CountStats pendingDepth;

  /// Characters the coalescer was holding when this chunk arrived.
  ///
  /// A buffer that grows across arrivals and empties on frames is batching
  /// doing its job; one that reads zero every time is a batch handed over per
  /// chunk, which is no batching at all.
  final CountStats bufferedChars;

  /// Wall time between one chunk arriving and the next. The isolate has to
  /// return to the event loop for a chunk to be delivered, so a long gap is a
  /// stretch where nothing else — a frame included — could run either.
  final DurationStats arrivalGap;

  /// Every chunk seen in the window, including ones the sample buffer has
  /// since dropped.
  ///
  /// [chunkChars] describes a *retained sample*, so once the buffer overflows
  /// its `total` covers the tail of the run rather than the run. A benchmark
  /// that pushes gigabytes through 1 KiB reads overflows within seconds, and
  /// reading the sample total as the window's throughput understates it by
  /// however much was dropped — which is the shape of an error that gets
  /// published. These two counters never drop anything.
  final int totalChunks;
  final int totalChars;

  double get wallClockMs => wallClockMicros / 1000;

  /// Throughput over the window, counting decoded characters.
  double get charsPerSecond =>
      wallClockMicros == 0 ? 0 : totalChars * 1000000 / wallClockMicros;

  /// Stream events delivered per second.
  ///
  /// The number to compare against the terminal's parse rate: when a PTY
  /// hands over 1 KiB at a time, this is what actually caps throughput.
  double get chunksPerSecond =>
      wallClockMicros == 0 ? 0 : totalChunks * 1000000 / wallClockMicros;

  /// Whether the sample buffer overflowed, so [chunkChars] and [pendingDepth]
  /// describe the tail of the window rather than all of it.
  bool get sampled => chunkChars.sampleCount < totalChunks;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'wall_clock_ms': double.parse(wallClockMs.toStringAsFixed(2)),
    'total_chunks': totalChunks,
    'total_chars': totalChars,
    'chars_per_second': charsPerSecond.round(),
    'chunks_per_second': chunksPerSecond.round(),
    'sampled': sampled,
    'chunk_chars': chunkChars.toJson(),
    'pending_depth': pendingDepth.toJson(),
    'buffered_chars': bufferedChars.toJson(),
    'arrival_gap_ms': arrivalGap.toJson(),
  };

  String toReportLine() =>
      '$kWritePathReportMarker ${jsonEncode(toJson())}';
}

/// Records what the terminal bridges hand to the paced writer.
///
/// Frame timings say the UI isolate disappears for tens of seconds during a
/// benchmark while the frames it does produce are fast. That narrows the cost
/// to work outside the frame pipeline, but not to a cause: a single enormous
/// chunk parsed atomically, and thousands of small chunks each drained inline
/// without ever forming a backlog, produce the same frame trace. The three
/// series here tell those apart — chunk size, queue depth on arrival, and the
/// gap between arrivals.
class WritePathMetrics {
  WritePathMetrics({this.maxSamples = 200000});

  /// Upper bound on retained chunks. Past it the oldest half is dropped, so a
  /// recorder left running cannot grow without limit.
  final int maxSamples;

  final List<int> _chunkChars = <int>[];
  final List<int> _pendingDepth = <int>[];
  final List<int> _bufferedChars = <int>[];
  final List<int> _arrivalGapMicros = <int>[];

  bool _recording = false;
  int? _startedAtMicros;
  int _lastArrivalMicros = 0;
  int _stoppedWallClockMicros = 0;
  int _totalChunks = 0;
  int _totalChars = 0;

  bool get isRecording => _recording;

  /// Retained samples, which is not the window's chunk count once the buffer
  /// has overflowed — see [WritePathSnapshot.totalChunks].
  int get chunkCount => _chunkChars.length;

  void start() {
    if (_recording) return;
    reset();
    _recording = true;
    _startedAtMicros = _nowMicros();
  }

  void stop() {
    if (!_recording) return;
    _recording = false;
    _stoppedWallClockMicros = _nowMicros() - (_startedAtMicros ?? _nowMicros());
  }

  void reset() {
    _chunkChars.clear();
    _pendingDepth.clear();
    _bufferedChars.clear();
    _arrivalGapMicros.clear();
    _startedAtMicros = null;
    _lastArrivalMicros = 0;
    _stoppedWallClockMicros = 0;
    _totalChunks = 0;
    _totalChars = 0;
  }

  /// Records one chunk on its way into the paced writer.
  ///
  /// [pendingChunks] is the writer's queue depth *before* this chunk is
  /// queued, which is what says whether the pacer had a backlog to pace.
  void recordChunk({
    required int chars,
    required int pendingChunks,
    int bufferedChars = 0,
  }) {
    if (!_recording) return;
    final now = _nowMicros();
    // The first chunk has nothing to measure a gap against; timing it from
    // the recorder's start would score the user's walk to the keyboard.
    if (_lastArrivalMicros != 0) {
      _arrivalGapMicros.add(now - _lastArrivalMicros);
    }
    _lastArrivalMicros = now;
    _totalChunks++;
    _totalChars += chars;
    _chunkChars.add(chars);
    _pendingDepth.add(pendingChunks);
    _bufferedChars.add(bufferedChars);
    if (_chunkChars.length > maxSamples) _dropOldestHalf();
  }

  WritePathSnapshot snapshot({String label = 'unnamed'}) {
    final wallClock = _recording
        ? _nowMicros() - (_startedAtMicros ?? _nowMicros())
        : _stoppedWallClockMicros;
    return WritePathSnapshot(
      label: label,
      wallClockMicros: wallClock,
      chunkChars: CountStats.fromSorted(_sortedCopy(_chunkChars)),
      pendingDepth: CountStats.fromSorted(_sortedCopy(_pendingDepth)),
      bufferedChars: CountStats.fromSorted(_sortedCopy(_bufferedChars)),
      arrivalGap: DurationStats.fromSortedMicros(_sortedCopy(_arrivalGapMicros)),
      totalChunks: _totalChunks,
      totalChars: _totalChars,
    );
  }

  /// Stops the window and prints its report line.
  WritePathSnapshot stopAndReport({String label = 'unnamed'}) {
    stop();
    final result = snapshot(label: label);
    // ignore: avoid_print
    print(result.toReportLine());
    return result;
  }

  void _dropOldestHalf() {
    final keepFrom = _chunkChars.length ~/ 2;
    _chunkChars.removeRange(0, keepFrom);
    _pendingDepth.removeRange(0, keepFrom);
    _bufferedChars.removeRange(0, keepFrom);
    if (_arrivalGapMicros.length > keepFrom) {
      _arrivalGapMicros.removeRange(0, keepFrom);
    }
  }

  static List<int> _sortedCopy(List<int> values) =>
      List<int>.of(values)..sort();

  static int _nowMicros() => DateTime.now().microsecondsSinceEpoch;
}

/// The recorder the terminal bridges report into.
final WritePathMetrics writePathMetrics = WritePathMetrics();

/// Whether a bridge should pay for the bookkeeping at all.
///
/// The check is on the compile-time define, so a release build drops the
/// recording call entirely rather than testing a flag per PTY chunk.
bool get isWritePathInstrumented => kPerfInstrumentationEnabled;
