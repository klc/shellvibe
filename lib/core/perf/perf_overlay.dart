import 'dart:async';

import 'package:flutter/widgets.dart';

import 'frame_metrics.dart';
import 'write_path_metrics.dart';

/// Live frame-timing readout drawn above the whole app.
///
/// Sits outside `MaterialApp` so it survives route changes and cannot be
/// repainted by the screen under test — a benchmark HUD that rebuilds with the
/// terminal would be measuring itself.
///
/// Tap toggles recording, long-press prints the report line and clears.
class PerfOverlayHost extends StatefulWidget {
  const PerfOverlayHost({required this.child, super.key});

  final Widget child;

  /// Wraps [child] only when the build was compiled with the perf define, so
  /// a normal build carries neither the widget nor the polling timer.
  static Widget maybeWrap(Widget child) =>
      kPerfInstrumentationEnabled ? PerfOverlayHost(child: child) : child;

  @override
  State<PerfOverlayHost> createState() => _PerfOverlayHostState();
}

class _PerfOverlayHostState extends State<PerfOverlayHost> {
  /// Two refreshes a second: fast enough to watch a dump land, slow enough
  /// that the HUD's own rebuild does not pollute the numbers it reports.
  static const Duration _pollInterval = Duration(milliseconds: 500);

  Timer? _timer;
  FrameMetricsSnapshot? _snapshot;
  String _label = 'idle';

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _snapshot = frameMetrics.snapshot(label: _label);
    });
  }

  void _toggleRecording() {
    setState(() {
      if (frameMetrics.isRecording) {
        _snapshot = frameMetrics.stopAndReport(label: _label);
        // Frame timings say the isolate vanished; the write-path line says
        // what it was carrying when it did. They are only readable together,
        // so one gesture starts and stops both.
        writePathMetrics.stopAndReport(label: _label);
      } else {
        _label = 'manual-${DateTime.now().toIso8601String()}';
        frameMetrics.start();
        writePathMetrics.start();
      }
    });
  }

  void _dumpAndReset() {
    setState(() {
      frameMetrics.stopAndReport(label: _label);
      writePathMetrics.stopAndReport(label: _label);
      frameMetrics.reset();
      writePathMetrics.reset();
      // The report line is already on stdout, which is where the runner reads
      // it. Keeping the dumped snapshot on screen after clearing would leave
      // the HUD claiming frames the recorder no longer holds.
      _snapshot = null;
      _label = 'idle';
    });
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQueryData.fromView(View.of(context)).padding;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: <Widget>[
          widget.child,
          Positioned(
            top: padding.top + 8,
            right: 8,
            child: GestureDetector(
              onTap: _toggleRecording,
              onLongPress: _dumpAndReset,
              child: _PerfReadout(
                snapshot: _snapshot,
                recording: frameMetrics.isRecording,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PerfReadout extends StatelessWidget {
  const _PerfReadout({required this.snapshot, required this.recording});

  final FrameMetricsSnapshot? snapshot;
  final bool recording;

  static const TextStyle _style = TextStyle(
    fontFamily: 'RobotoMono',
    fontSize: 11,
    height: 1.35,
    color: Color(0xFFE6E6E6),
    decoration: TextDecoration.none,
  );

  @override
  Widget build(BuildContext context) {
    final data = snapshot;
    final lines = <String>[
      recording ? '● REC  ${data?.label ?? ''}' : '○ idle  (tap to record)',
      if (data != null && data.frameCount > 0) ...<String>[
        'frames ${data.frameCount}  ${data.refreshRateHz.round()}Hz',
        'build  p50 ${_ms(data.build.p50Ms)} p95 ${_ms(data.build.p95Ms)}',
        'raster p50 ${_ms(data.raster.p50Ms)} p95 ${_ms(data.raster.p95Ms)}',
        'total  p99 ${_ms(data.total.p99Ms)} max ${_ms(data.total.maxMs)}',
        'jank   ${data.jankFrames} '
            '(${(data.jankRatio * 100).toStringAsFixed(1)}%)',
      ] else
        'no frames yet',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE6101010),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: recording ? const Color(0xFFE05252) : const Color(0xFF3A3A3A),
        ),
      ),
      child: Text(lines.join('\n'), style: _style),
    );
  }

  static String _ms(double value) => '${value.toStringAsFixed(1)}ms';
}
