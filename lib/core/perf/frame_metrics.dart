import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Whether frame instrumentation is compiled in.
///
/// Gated behind a `--dart-define` rather than [kDebugMode] on purpose: the
/// numbers that matter come from `--profile`, where debug-mode asserts and the
/// unoptimised widget layer are gone. A debug-mode benchmark is 5-10x slower
/// than what a user sees, so publishing one would be worse than publishing
/// nothing.
///
/// ```sh
/// flutter run --profile --dart-define=SHELLVIBE_PERF=true
/// ```
const bool kPerfInstrumentationEnabled = bool.fromEnvironment('SHELLVIBE_PERF');

/// Prefix on the single-line JSON the recorder prints, so a benchmark runner
/// can pull results straight out of `flutter run` stdout without a file path
/// handshake across the host/device boundary.
const String kPerfReportMarker = '[shellvibe-perf]';

/// Percentile summary of one timing series, in microseconds.
///
/// Terminal throughput is judged by the bad frames, not the average one: a run
/// that averages 8ms but spikes to 90ms reads as a stutter, while a steady 14ms
/// reads as smooth. So p95/p99 and [max] carry the verdict and [mean] is only
/// here to make a regression legible.
@immutable
class DurationStats {
  const DurationStats({
    required this.sampleCount,
    required this.meanMicros,
    required this.p50Micros,
    required this.p95Micros,
    required this.p99Micros,
    required this.maxMicros,
  });

  /// Builds a summary from an *already sorted* ascending list of microseconds.
  factory DurationStats.fromSortedMicros(List<int> sorted) {
    if (sorted.isEmpty) {
      return const DurationStats(
        sampleCount: 0,
        meanMicros: 0,
        p50Micros: 0,
        p95Micros: 0,
        p99Micros: 0,
        maxMicros: 0,
      );
    }
    var total = 0;
    for (final value in sorted) {
      total += value;
    }
    return DurationStats(
      sampleCount: sorted.length,
      meanMicros: total / sorted.length,
      p50Micros: _percentile(sorted, 0.50),
      p95Micros: _percentile(sorted, 0.95),
      p99Micros: _percentile(sorted, 0.99),
      maxMicros: sorted.last,
    );
  }

  final int sampleCount;
  final double meanMicros;
  final int p50Micros;
  final int p95Micros;
  final int p99Micros;
  final int maxMicros;

  double get meanMs => meanMicros / 1000;
  double get p50Ms => p50Micros / 1000;
  double get p95Ms => p95Micros / 1000;
  double get p99Ms => p99Micros / 1000;
  double get maxMs => maxMicros / 1000;

  /// Nearest-rank percentile: the smallest sample at or above the requested
  /// fraction of the run. Chosen over interpolation because a frame time is an
  /// observation that actually happened — an interpolated p99 of 21.4ms names
  /// a frame nobody rendered.
  static int _percentile(List<int> sorted, double fraction) {
    final rank = (fraction * sorted.length).ceil();
    final index = (rank - 1).clamp(0, sorted.length - 1);
    return sorted[index];
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'samples': sampleCount,
    'mean_ms': _round(meanMs),
    'p50_ms': _round(p50Ms),
    'p95_ms': _round(p95Ms),
    'p99_ms': _round(p99Ms),
    'max_ms': _round(maxMs),
  };
}

/// One finished measurement window.
@immutable
class FrameMetricsSnapshot {
  const FrameMetricsSnapshot({
    required this.label,
    required this.refreshRateHz,
    required this.frameBudgetMicros,
    required this.build,
    required this.raster,
    required this.total,
    required this.jankFrames,
    required this.wallClockMicros,
  });

  /// Free-form name of the scenario being measured, e.g. `vtebench:scrolling`.
  final String label;
  final double refreshRateHz;

  /// One vsync interval. A frame slower than this missed its deadline.
  final int frameBudgetMicros;

  /// UI-thread work: widget build + layout + paint recording.
  final DurationStats build;

  /// GPU-thread work: turning the recorded layer tree into pixels.
  final DurationStats raster;

  /// Vsync to raster finish — what the eye actually waits for.
  final DurationStats total;

  /// Frames whose [total] exceeded [frameBudgetMicros].
  final int jankFrames;

  /// Wall-clock length of the window, so throughput scenarios can be compared
  /// on "how long did the whole dump take" as well as on frame quality.
  final int wallClockMicros;

  int get frameCount => total.sampleCount;

  /// Share of frames that missed the deadline, 0.0-1.0.
  double get jankRatio => frameCount == 0 ? 0 : jankFrames / frameCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'refresh_rate_hz': _round(refreshRateHz),
    'frame_budget_ms': _round(frameBudgetMicros / 1000),
    'frames': frameCount,
    'jank_frames': jankFrames,
    'jank_ratio': _round(jankRatio, 4),
    'wall_clock_ms': _round(wallClockMicros / 1000),
    'build': build.toJson(),
    'raster': raster.toJson(),
    'total': total.toJson(),
  };

  /// Single-line JSON, marker-prefixed for the benchmark runner to grep.
  String toReportLine() => '$kPerfReportMarker ${jsonEncode(toJson())}';
}

/// Collects per-frame timings from the engine.
///
/// This is the only honest way to back a "stays at 60fps" claim: external
/// terminal benchmarks (vtebench, termbench) time a whole dump and cannot say
/// whether the frames inside it were smooth or a slideshow that finished fast.
class FrameMetricsRecorder {
  FrameMetricsRecorder({this.maxSamples = 120000});

  /// Upper bound on retained frames, ~33 minutes at 60Hz. Past it the oldest
  /// samples are dropped so a forgotten recorder cannot grow without limit.
  final int maxSamples;

  final List<int> _buildMicros = <int>[];
  final List<int> _rasterMicros = <int>[];
  final List<int> _totalMicros = <int>[];

  bool _recording = false;
  int? _startedAtMicros;
  int _stoppedWallClockMicros = 0;
  TimingsCallback? _callback;

  bool get isRecording => _recording;
  int get frameCount => _totalMicros.length;

  /// Display refresh rate, falling back to 60Hz when the platform does not
  /// report one (headless test binding, some Linux compositors).
  double get refreshRateHz {
    final rate = PlatformDispatcher.instance.implicitView?.display.refreshRate;
    if (rate == null || !rate.isFinite || rate <= 0) return 60;
    return rate;
  }

  int get frameBudgetMicros => (1000000 / refreshRateHz).round();

  /// Starts a measurement window, discarding anything already collected.
  void start() {
    if (_recording) return;
    reset();
    _recording = true;
    _startedAtMicros = _nowMicros();
    final callback = _onTimings;
    _callback = callback;
    SchedulerBinding.instance.addTimingsCallback(callback);
  }

  /// Stops the window. Safe to call when not recording.
  void stop() {
    if (!_recording) return;
    _recording = false;
    _stoppedWallClockMicros = _nowMicros() - (_startedAtMicros ?? _nowMicros());
    final callback = _callback;
    if (callback != null) {
      SchedulerBinding.instance.removeTimingsCallback(callback);
      _callback = null;
    }
  }

  void reset() {
    _buildMicros.clear();
    _rasterMicros.clear();
    _totalMicros.clear();
    _startedAtMicros = null;
    _stoppedWallClockMicros = 0;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      recordRaw(
        buildMicros: timing.buildDuration.inMicroseconds,
        rasterMicros: timing.rasterDuration.inMicroseconds,
        totalMicros: timing.totalSpan.inMicroseconds,
      );
    }
  }

  /// Ingests one frame's timings directly.
  ///
  /// Kept separate from the engine callback so tests can feed a known series
  /// without constructing a [FrameTiming], whose constructor signature moves
  /// between Flutter versions.
  @visibleForTesting
  void recordRaw({
    required int buildMicros,
    required int rasterMicros,
    required int totalMicros,
  }) {
    if (_buildMicros.length >= maxSamples) {
      // Drop the oldest half in one pass instead of shifting the whole list
      // once per frame. A measurement tool that itself burns milliseconds on
      // the UI thread would show up in the very numbers it is reporting.
      _dropOldestHalf();
    }
    _buildMicros.add(buildMicros);
    _rasterMicros.add(rasterMicros);
    _totalMicros.add(totalMicros);
  }

  /// Summarises what has been collected so far. Does not stop the window, so
  /// a live overlay can poll it.
  FrameMetricsSnapshot snapshot({String label = 'unlabelled'}) {
    final budget = frameBudgetMicros;
    var jank = 0;
    for (final micros in _totalMicros) {
      if (micros > budget) jank++;
    }
    final elapsed = _recording && _startedAtMicros != null
        ? _nowMicros() - _startedAtMicros!
        : _stoppedWallClockMicros;

    return FrameMetricsSnapshot(
      label: label,
      refreshRateHz: refreshRateHz,
      frameBudgetMicros: budget,
      build: DurationStats.fromSortedMicros(_sortedCopy(_buildMicros)),
      raster: DurationStats.fromSortedMicros(_sortedCopy(_rasterMicros)),
      total: DurationStats.fromSortedMicros(_sortedCopy(_totalMicros)),
      jankFrames: jank,
      wallClockMicros: elapsed,
    );
  }

  /// Stops the window and prints the report line the runner greps for.
  FrameMetricsSnapshot stopAndReport({String label = 'unlabelled'}) {
    stop();
    final snapshot = this.snapshot(label: label);
    // Deliberately `print`, not `debugPrint`: debugPrint wraps long output
    // across lines, which would split the JSON the runner has to parse.
    // ignore: avoid_print
    print(snapshot.toReportLine());
    return snapshot;
  }

  void _dropOldestHalf() {
    final keep = maxSamples ~/ 2;
    for (final series in <List<int>>[
      _buildMicros,
      _rasterMicros,
      _totalMicros,
    ]) {
      series.replaceRange(0, series.length - keep, const <int>[]);
    }
  }

  static List<int> _sortedCopy(List<int> values) =>
      List<int>.of(values)..sort();

  int _nowMicros() => DateTime.now().microsecondsSinceEpoch;
}

/// Process-wide recorder used by the overlay and the benchmark runner.
final FrameMetricsRecorder frameMetrics = FrameMetricsRecorder();

double _round(double value, [int digits = 2]) {
  if (!value.isFinite) return 0;
  final factor = <int, double>{2: 100.0, 4: 10000.0}[digits] ?? 100.0;
  return (value * factor).round() / factor;
}
