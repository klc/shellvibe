import 'package:flutter/material.dart';

import '../../domain/models/terminal_tab_session.dart';

/// Draggable split container used for terminal split panes.
///
/// Lays [first] and [second] out along [axis] with [ratio] as the share of
/// [second]; a 10px-wide draggable divider sits between them (2px visual
/// line in [dividerColor]). Dragging updates [onRatioChanged] with the new
/// [second] share, clamped to [kSplitPaneMinRatio]..[kSplitPaneMaxRatio].
///
/// [axis] matches `TerminalTabSession.splitDirection` semantics:
/// `Axis.horizontal` = side-by-side Row, `Axis.vertical` = stacked Column.
///
/// Each split level gets its own [LayoutBuilder], so nested splits compose:
/// a child divider only ever drags within its own container.
///
/// While a drag is in flight the ratio lives in this widget's own state and
/// [onRatioChanged] is called once, on drag end. That keeps the per-frame cost
/// to a relayout: [first] and [second] are handed down as the same widget
/// instances, so their subtrees (whole terminal views) are not rebuilt.
/// Reporting every pointer move to the notifier instead would rebuild the
/// entire pane tree on each frame of the gesture.
class ResizableSplit extends StatefulWidget {
  /// Left pane (Axis.horizontal) or top pane (Axis.vertical).
  final Widget first;

  /// Right pane (Axis.horizontal) or bottom pane (Axis.vertical) — the pane
  /// whose share [ratio] describes.
  final Widget second;

  /// Lay the two panes out along this axis.
  final Axis axis;

  /// Share (0..1) of the container taken by [second]; must be clamped by the
  /// caller (this widget clamps on drag).
  final double ratio;

  /// Called with [second]'s new share when a drag ends, already clamped.
  final ValueChanged<double> onRatioChanged;

  final Color dividerColor;

  /// Widget key placed on the draggable divider (for tests / semantics).
  final Key? dividerKey;

  const ResizableSplit({
    super.key,
    required this.first,
    required this.second,
    required this.axis,
    required this.ratio,
    required this.onRatioChanged,
    required this.dividerColor,
    this.dividerKey,
  });

  static const double _hit = 10;
  static const double _visual = 2;
  static const int _flexUnits = 1000;

  @override
  State<ResizableSplit> createState() => _ResizableSplitState();
}

class _ResizableSplitState extends State<ResizableSplit> {
  /// Ratio being dragged, or null when [ResizableSplit.ratio] is authoritative.
  double? _dragRatio;

  /// Ratio at drag start plus the deltas accumulated since, so the result
  /// stays correct even if the parent rebuilds mid-gesture.
  double _startRatio = 0.5;
  double _dragTotal = 0;

  double get _ratio => _dragRatio ?? widget.ratio;

  @override
  void didUpdateWidget(ResizableSplit oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The owner published a ratio (ours, after a drag, or someone else's);
    // hand authority back to it.
    if (widget.ratio != oldWidget.ratio) _dragRatio = null;
  }

  void _handleStart() {
    _dragTotal = 0;
    _startRatio = _ratio;
  }

  void _handleUpdate(double delta, double total) {
    if (total <= 0) return;
    _dragTotal += delta;
    // The divider sits between the panes at the boundary of [first]. Moving
    // the pointer right/down (positive delta) must push the divider right/
    // down, i.e. grow [first]; since ratio is [second]'s share, subtract.
    setState(() {
      _dragRatio = (_startRatio - _dragTotal / total)
          .clamp(kSplitPaneMinRatio, kSplitPaneMaxRatio);
    });
  }

  void _handleEnd() {
    final ratio = _dragRatio;
    if (ratio != null) widget.onRatioChanged(ratio);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = widget.axis == Axis.vertical
            ? constraints.maxHeight
            : constraints.maxWidth;

        final secondFlex = (_ratio * ResizableSplit._flexUnits)
            .round()
            .clamp(1, ResizableSplit._flexUnits - 1);
        final firstFlex = ResizableSplit._flexUnits - secondFlex;

        final divider = _SplitDivider(
          axis: widget.axis,
          color: widget.dividerColor,
          key: widget.dividerKey ?? const ValueKey('split_divider'),
          onDragStart: _handleStart,
          onDragUpdate: (delta) => _handleUpdate(delta, total),
          onDragEnd: _handleEnd,
        );

        if (widget.axis == Axis.vertical) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: firstFlex, child: widget.first),
              divider,
              Expanded(flex: secondFlex, child: widget.second),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: firstFlex, child: widget.first),
            divider,
            Expanded(flex: secondFlex, child: widget.second),
          ],
        );
      },
    );
  }
}

/// The draggable 10px-wide grip between two panes (2px visual line in
/// [color]). Reports raw pointer deltas along [axis]; the owning
/// [ResizableSplit] turns them into a ratio.
class _SplitDivider extends StatelessWidget {
  final Axis axis;
  final Color color;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  const _SplitDivider({
    super.key,
    required this.axis,
    required this.color,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final isHorizontal = axis == Axis.horizontal;
    return MouseRegion(
      cursor: isHorizontal
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: isHorizontal ? (_) => onDragStart() : null,
        onHorizontalDragUpdate:
            isHorizontal ? (d) => onDragUpdate(d.delta.dx) : null,
        onHorizontalDragEnd: isHorizontal ? (_) => onDragEnd() : null,
        onVerticalDragStart: isHorizontal ? null : (_) => onDragStart(),
        onVerticalDragUpdate:
            isHorizontal ? null : (d) => onDragUpdate(d.delta.dy),
        onVerticalDragEnd: isHorizontal ? null : (_) => onDragEnd(),
        child: SizedBox(
          width: isHorizontal ? ResizableSplit._hit : double.infinity,
          height: isHorizontal ? double.infinity : ResizableSplit._hit,
          child: Center(
            child: Container(
              width: isHorizontal ? ResizableSplit._visual : null,
              height: isHorizontal ? null : ResizableSplit._visual,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
