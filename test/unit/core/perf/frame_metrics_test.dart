import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/perf/frame_metrics.dart';

void main() {
  group('DurationStats', () {
    test('empty series reports zeroes rather than throwing', () {
      final stats = DurationStats.fromSortedMicros(<int>[]);
      expect(stats.sampleCount, equals(0));
      expect(stats.p50Micros, equals(0));
      expect(stats.maxMicros, equals(0));
      expect(stats.meanMicros, equals(0));
    });

    test('percentiles use nearest rank, so every value is a real sample', () {
      // 1..100 ms in microseconds.
      final sorted = List<int>.generate(100, (i) => (i + 1) * 1000);
      final stats = DurationStats.fromSortedMicros(sorted);

      expect(stats.sampleCount, equals(100));
      expect(stats.p50Ms, equals(50));
      expect(stats.p95Ms, equals(95));
      expect(stats.p99Ms, equals(99));
      expect(stats.maxMs, equals(100));
      expect(stats.meanMs, closeTo(50.5, 0.001));
    });

    test('single sample answers every percentile with itself', () {
      final stats = DurationStats.fromSortedMicros(<int>[7000]);
      expect(stats.p50Ms, equals(7));
      expect(stats.p99Ms, equals(7));
      expect(stats.maxMs, equals(7));
    });
  });

  group('FrameMetricsRecorder', () {
    test('counts a frame as jank only when it overruns the vsync budget', () {
      final recorder = FrameMetricsRecorder();
      final budget = recorder.frameBudgetMicros;

      // Two comfortable frames, one exactly at budget (still on time),
      // and one that overruns.
      recorder
        ..recordRaw(buildMicros: 1000, rasterMicros: 2000, totalMicros: 4000)
        ..recordRaw(buildMicros: 1200, rasterMicros: 2100, totalMicros: 5000)
        ..recordRaw(
          buildMicros: 1300,
          rasterMicros: 2200,
          totalMicros: budget,
        )
        ..recordRaw(
          buildMicros: 9000,
          rasterMicros: 30000,
          totalMicros: budget * 3,
        );

      final snapshot = recorder.snapshot(label: 'jank-test');
      expect(snapshot.frameCount, equals(4));
      expect(snapshot.jankFrames, equals(1));
      expect(snapshot.jankRatio, closeTo(0.25, 0.0001));
      expect(snapshot.total.maxMicros, equals(budget * 3));
    });

    test('build and raster series stay separate', () {
      final recorder = FrameMetricsRecorder()
        ..recordRaw(buildMicros: 1000, rasterMicros: 8000, totalMicros: 9000)
        ..recordRaw(buildMicros: 2000, rasterMicros: 9000, totalMicros: 11000);

      final snapshot = recorder.snapshot();
      expect(snapshot.build.maxMs, equals(2));
      expect(snapshot.raster.maxMs, equals(9));
      expect(snapshot.total.maxMs, equals(11));
    });

    test('drops the oldest samples once maxSamples is reached', () {
      final recorder = FrameMetricsRecorder(maxSamples: 3);
      for (var i = 1; i <= 5; i++) {
        recorder.recordRaw(
          buildMicros: i * 1000,
          rasterMicros: i * 1000,
          totalMicros: i * 1000,
        );
      }

      final snapshot = recorder.snapshot();
      expect(snapshot.frameCount, equals(3));
      // Frames 3, 4, 5 survived; 1 and 2 were evicted.
      expect(snapshot.total.p50Ms, equals(4));
      expect(snapshot.total.maxMs, equals(5));
    });

    test('stays bounded and keeps the newest frames over a long run', () {
      const cap = 100;
      final recorder = FrameMetricsRecorder(maxSamples: cap);
      for (var i = 1; i <= 10000; i++) {
        recorder.recordRaw(
          buildMicros: i,
          rasterMicros: i,
          totalMicros: i * 1000,
        );
      }

      // Eviction drops half the window at a time, so the count sits between
      // half the cap and the cap — never above it.
      expect(recorder.frameCount, lessThanOrEqualTo(cap));
      expect(recorder.frameCount, greaterThan(cap ~/ 2));
      // Whatever survived is the tail of the run, not the head.
      expect(recorder.snapshot().total.maxMs, equals(10000));
    });

    test('reset clears the window', () {
      final recorder = FrameMetricsRecorder()
        ..recordRaw(buildMicros: 1000, rasterMicros: 1000, totalMicros: 1000);
      expect(recorder.frameCount, equals(1));

      recorder.reset();
      expect(recorder.frameCount, equals(0));
      expect(recorder.snapshot().jankFrames, equals(0));
    });

    test('stop is a no-op when the recorder was never started', () {
      final recorder = FrameMetricsRecorder();
      expect(recorder.isRecording, isFalse);
      expect(recorder.stop, returnsNormally);
      expect(recorder.isRecording, isFalse);
    });
  });

  group('FrameMetricsSnapshot report line', () {
    test('marker-prefixed payload parses as one JSON object', () {
      final recorder = FrameMetricsRecorder()
        ..recordRaw(buildMicros: 1500, rasterMicros: 3500, totalMicros: 6000);
      final line = recorder.snapshot(label: 'vtebench:scrolling').toReportLine();

      expect(line, startsWith(kPerfReportMarker));
      expect(line, isNot(contains('\n')));

      final payload = line.substring(kPerfReportMarker.length).trim();
      final decoded = jsonDecode(payload) as Map<String, Object?>;

      expect(decoded['label'], equals('vtebench:scrolling'));
      expect(decoded['frames'], equals(1));
      expect(decoded['jank_frames'], equals(0));
      expect((decoded['build']! as Map<String, Object?>)['p50_ms'], equals(1.5));
      expect(
        (decoded['raster']! as Map<String, Object?>)['p50_ms'],
        equals(3.5),
      );
    });
  });
}
