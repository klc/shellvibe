import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/perf/write_path_metrics.dart';

void main() {
  group('CountStats', () {
    test('empty series reports zeroes rather than throwing', () {
      final stats = CountStats.fromSorted(<int>[]);
      expect(stats.sampleCount, equals(0));
      expect(stats.p50, equals(0));
      expect(stats.max, equals(0));
      expect(stats.total, equals(0));
    });

    test('percentiles use nearest rank, so every value is a real sample', () {
      final stats = CountStats.fromSorted(List<int>.generate(100, (i) => i + 1));

      expect(stats.sampleCount, equals(100));
      expect(stats.p50, equals(50));
      expect(stats.p95, equals(95));
      expect(stats.p99, equals(99));
      expect(stats.max, equals(100));
      expect(stats.mean, closeTo(50.5, 0.001));
      expect(stats.total, equals(5050));
    });
  });

  group('WritePathMetrics', () {
    test('records nothing until a window is open', () {
      final metrics = WritePathMetrics();
      metrics.recordChunk(chars: 4096, pendingChunks: 0);

      expect(metrics.chunkCount, equals(0));
    });

    test('keeps chunk sizes and both stage depths as separate series', () {
      final metrics = WritePathMetrics()..start();
      metrics.recordChunk(chars: 1024, pendingChunks: 0);
      metrics.recordChunk(chars: 8192, pendingChunks: 3, bufferedChars: 4096);
      metrics.stop();

      final snapshot = metrics.snapshot(label: 'test');
      expect(snapshot.chunkChars.total, equals(9216));
      expect(snapshot.chunkChars.max, equals(8192));
      expect(snapshot.pendingDepth.max, equals(3));
      expect(snapshot.bufferedChars.max, equals(4096));
    });

    test('a coalescer that never holds anything reads as zero throughout', () {
      // The shape that says batching is not engaging: every chunk arrives to
      // an empty buffer because the one before it was handed over alone.
      final metrics = WritePathMetrics()..start();
      for (var i = 0; i < 5; i++) {
        metrics.recordChunk(chars: 1024, pendingChunks: 0);
      }
      metrics.stop();

      expect(metrics.snapshot().bufferedChars.max, equals(0));
    });

    test('the first chunk contributes no arrival gap', () {
      // Otherwise the gap series would open with the time between the HUD
      // being tapped and the first byte arriving, which measures the user.
      final metrics = WritePathMetrics()..start();
      metrics.recordChunk(chars: 512, pendingChunks: 0);
      metrics.stop();

      expect(metrics.snapshot().arrivalGap.sampleCount, equals(0));

      metrics
        ..start()
        ..recordChunk(chars: 512, pendingChunks: 0)
        ..recordChunk(chars: 512, pendingChunks: 0)
        ..stop();

      expect(metrics.snapshot().arrivalGap.sampleCount, equals(1));
    });

    test('start discards whatever the previous window collected', () {
      final metrics = WritePathMetrics()..start();
      metrics.recordChunk(chars: 4096, pendingChunks: 0);
      metrics.stop();

      metrics.start();
      expect(metrics.chunkCount, equals(0));
    });

    test('a full recorder drops its oldest half instead of growing', () {
      final metrics = WritePathMetrics(maxSamples: 10)..start();
      for (var i = 0; i < 12; i++) {
        metrics.recordChunk(chars: i, pendingChunks: i);
      }

      expect(metrics.chunkCount, lessThanOrEqualTo(10));
      // The survivors are the recent ones: the first chunks are gone.
      expect(metrics.snapshot().chunkChars.max, equals(11));
    });

    test('the lifetime counters survive a buffer overflow', () {
      // The sample total covers only what is still retained, which is why
      // throughput has to be read off counters that never drop: a real run
      // overflows in seconds and the sample total then understates the
      // window by however much went overboard.
      final metrics = WritePathMetrics(maxSamples: 10)..start();
      for (var i = 0; i < 100; i++) {
        metrics.recordChunk(chars: 1024, pendingChunks: 0);
      }
      metrics.stop();

      final snapshot = metrics.snapshot();
      expect(snapshot.totalChunks, equals(100));
      expect(snapshot.totalChars, equals(102400));
      expect(snapshot.sampled, isTrue);
      expect(snapshot.chunkChars.total, lessThan(snapshot.totalChars));
    });

    test('a window that fits reports itself as unsampled', () {
      final metrics = WritePathMetrics()..start();
      metrics.recordChunk(chars: 1024, pendingChunks: 0);
      metrics.stop();

      expect(metrics.snapshot().sampled, isFalse);
    });

    test('the report line is one marker followed by parsable JSON', () {
      final metrics = WritePathMetrics()..start();
      metrics.recordChunk(chars: 65536, pendingChunks: 7);
      metrics.stop();

      final line = metrics.snapshot(label: 'window-1').toReportLine();
      expect(line, startsWith(kWritePathReportMarker));

      final json =
          jsonDecode(line.substring(kWritePathReportMarker.length + 1))
              as Map<String, Object?>;
      expect(json['label'], equals('window-1'));
      expect(
        (json['chunk_chars']! as Map<String, Object?>)['max'],
        equals(65536),
      );
      expect(
        (json['pending_depth']! as Map<String, Object?>)['max'],
        equals(7),
      );
    });
  });
}
