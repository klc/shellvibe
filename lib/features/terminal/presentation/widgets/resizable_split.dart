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
class ResizableSplit extends StatelessWidget {
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

  /// Called with [second]'s new share while dragging, already clamped.
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = axis == Axis.vertical
            ? constraints.maxHeight
            : constraints.maxWidth;

        final secondFlex =
            (ratio * _flexUnits).round().clamp(1, _flexUnits - 1);
        final firstFlex = _flexUnits - secondFlex;

        final divider = _SplitDivider(
          axis: axis,
          total: total,
          color: dividerColor,
          key: dividerKey ?? const ValueKey('split_divider'),
          ratio: ratio,
          onRatioChanged: onRatioChanged,
        );

        if (axis == Axis.vertical) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: firstFlex, child: first),
              divider,
              Expanded(flex: secondFlex, child: second),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: firstFlex, child: first),
            divider,
            Expanded(flex: secondFlex, child: second),
          ],
        );
      },
    );
  }
}

/// The draggable 10px-wide grip between two panes (2px visual line in
/// [color]). Accumulates drag deltas across pointer events relative to the
/// ratio captured at drag start, so the result stays correct even when the
/// parent rebuilds (and hands new callbacks) mid-gesture.
class _SplitDivider extends StatefulWidget {
  final Axis axis;
  final double total;
  final Color color;
  final double ratio;
  final ValueChanged<double> onRatioChanged;

  const _SplitDivider({
    super.key,
    required this.axis,
    required this.total,
    required this.color,
    required this.ratio,
    required this.onRatioChanged,
  });

  @override
  State<_SplitDivider> createState() => _SplitDividerState();
}

class _SplitDividerState extends State<_SplitDivider> {
  double _dragTotal = 0;
  double _startRatio = 0.5;

  void _handleStart() {
    _dragTotal = 0;
    _startRatio = widget.ratio;
  }

  void _handleUpdate(double delta) {
    _dragTotal += delta;
    // The divider sits between the panes at the boundary of [first]. Moving
    // the pointer right/down (positive delta) must push the divider right/
    // down, i.e. grow [first]; since ratio is [second]'s share, subtract.
    widget.onRatioChanged(
      (_startRatio - _dragTotal / widget.total)
          .clamp(kSplitPaneMinRatio, kSplitPaneMaxRatio),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: (widget.axis == Axis.horizontal)
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: widget.axis == Axis.horizontal
            ? (_) => _handleStart()
            : null,
        onHorizontalDragUpdate: widget.axis == Axis.horizontal
            ? (d) => _handleUpdate(d.delta.dx)
            : null,
        onVerticalDragStart: widget.axis == Axis.vertical
            ? (_) => _handleStart()
            : null,
        onVerticalDragUpdate: widget.axis == Axis.vertical
            ? (d) => _handleUpdate(d.delta.dy)
            : null,
        child: SizedBox(
          width: widget.axis == Axis.horizontal
              ? ResizableSplit._hit
              : double.infinity,
          height: widget.axis == Axis.vertical
              ? ResizableSplit._hit
              : double.infinity,
          child: Center(
            child: Container(
              width: widget.axis == Axis.horizontal
                  ? ResizableSplit._visual
                  : null,
              height: widget.axis == Axis.vertical
                  ? ResizableSplit._visual
                  : null,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}