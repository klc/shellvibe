import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/perf/frame_metrics.dart';
import 'package:shellvibe/core/perf/perf_overlay.dart';

void main() {
  Widget host() => const PerfOverlayHost(
    child: SizedBox.expand(child: Text('app', textDirection: TextDirection.ltr)),
  );

  tearDown(() {
    frameMetrics
      ..stop()
      ..reset();
  });

  testWidgets('renders above the app without needing a MaterialApp ancestor', (
    tester,
  ) async {
    await tester.pumpWidget(host());

    expect(find.text('app'), findsOneWidget);
    expect(find.textContaining('idle'), findsOneWidget);
    expect(find.textContaining('no frames yet'), findsOneWidget);
  });

  testWidgets('tap starts recording and flips the readout to REC', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    expect(frameMetrics.isRecording, isFalse);

    await tester.tap(find.textContaining('idle'));
    await tester.pump();

    expect(frameMetrics.isRecording, isTrue);
    expect(find.textContaining('REC'), findsOneWidget);
  });

  testWidgets('a second tap stops recording', (tester) async {
    await tester.pumpWidget(host());

    await tester.tap(find.textContaining('idle'));
    await tester.pump();
    await tester.tap(find.textContaining('REC'));
    await tester.pump();

    expect(frameMetrics.isRecording, isFalse);
  });

  testWidgets('the readout shows collected percentiles after a poll', (
    tester,
  ) async {
    await tester.pumpWidget(host());

    frameMetrics.recordRaw(
      buildMicros: 2000,
      rasterMicros: 4000,
      totalMicros: 7000,
    );
    // The overlay polls on a 500ms timer rather than on every frame.
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('frames 1'), findsOneWidget);
    expect(find.textContaining('build  p50 2.0ms'), findsOneWidget);
    expect(find.textContaining('raster p50 4.0ms'), findsOneWidget);
  });

  testWidgets('long-press clears the window back to idle', (tester) async {
    await tester.pumpWidget(host());

    await tester.tap(find.textContaining('idle'));
    await tester.pump();
    frameMetrics.recordRaw(
      buildMicros: 1000,
      rasterMicros: 1000,
      totalMicros: 1000,
    );

    await tester.longPress(find.textContaining('REC'));
    await tester.pump();

    expect(frameMetrics.isRecording, isFalse);
    expect(frameMetrics.frameCount, equals(0));
    expect(find.textContaining('no frames yet'), findsOneWidget);
  });

  testWidgets('maybeWrap leaves the tree untouched in a normal build', (
    tester,
  ) async {
    const child = Text('bare', textDirection: TextDirection.ltr);
    final wrapped = PerfOverlayHost.maybeWrap(child);

    // The perf define is off for `flutter test`, so this must be a pass-through.
    expect(kPerfInstrumentationEnabled, isFalse);
    expect(identical(wrapped, child), isTrue);

    await tester.pumpWidget(wrapped);
    expect(find.textContaining('idle'), findsNothing);
  });
}
