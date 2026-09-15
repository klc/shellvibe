import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../domain/models/terminal_tab_session.dart';

/// Drop half of the pane drag-and-drop: wraps one pane and turns a drop on it
/// into either a swap or a dock, depending on where inside the pane the pointer
/// was released.
///
/// The outer quarter along each side docks the dragged pane against that edge;
/// everything further in swaps the two panes. Corners go to whichever of the
/// two edges the pointer is nearer, so there is no dead zone and no
/// corner-shaped surprise.
///
/// Hover state lives here rather than in the tab view because it changes on
/// every pointer move: keeping it local means a hover repaints one pane's
/// overlay instead of rebuilding the pane tree, and [child] — a whole terminal
/// — is held as a field and never rebuilt by this widget at all.
class PaneDropTarget extends StatefulWidget {
  /// Panes that may be dropped here: the panes of this tab, minus this one.
  /// A drag from anywhere else is refused outright, so it never highlights.
  final Set<String> acceptedPaneIds;

  final ValueChanged<String> onSwap;
  final void Function(String paneId, PaneDockEdge edge) onDock;

  /// Corner radius of the pane, so the overlay cannot spill past its corners.
  final BorderRadius borderRadius;

  final ShellVibeTokens tokens;
  final Widget child;

  const PaneDropTarget({
    super.key,
    required this.acceptedPaneIds,
    required this.onSwap,
    required this.onDock,
    required this.borderRadius,
    required this.tokens,
    required this.child,
  });

  /// How much of each side docks rather than swaps.
  static const double edgeFraction = 0.25;

  @override
  State<PaneDropTarget> createState() => _PaneDropTargetState();
}

class _PaneDropTargetState extends State<PaneDropTarget> {
  bool _hovering = false;

  /// Edge the pointer is currently over, or null for the swap region.
  PaneDockEdge? _edge;

  /// Turns a global pointer position into the drop it would perform.
  ///
  /// Returns null while the pane has no size yet — a pane that has never been
  /// laid out cannot be under the pointer anyway.
  ({bool inside, PaneDockEdge? edge})? _resolve(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final size = box.size;
    if (size.width <= 0 || size.height <= 0) return null;

    final local = box.globalToLocal(globalPosition);
    final x = local.dx / size.width;
    final y = local.dy / size.height;

    // Distance to each side as a fraction of the pane, in edge order.
    final distances = <double>[x, 1 - x, y, 1 - y];
    final nearest = distances.reduce(min);
    if (nearest >= PaneDropTarget.edgeFraction) {
      return (inside: true, edge: null);
    }
    return (
      inside: true,
      edge: PaneDockEdge.values[distances.indexOf(nearest)],
    );
  }

  void _updateHover(Offset globalPosition) {
    final resolved = _resolve(globalPosition);
    if (resolved == null) return;
    if (_hovering && _edge == resolved.edge) return;
    setState(() {
      _hovering = true;
      _edge = resolved.edge;
    });
  }

  void _clearHover() {
    if (!_hovering) return;
    setState(() {
      _hovering = false;
      _edge = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          widget.acceptedPaneIds.contains(details.data),
      onMove: (details) => _updateHover(details.offset),
      onLeave: (_) => _clearHover(),
      onAcceptWithDetails: (details) {
        // Resolved again from the drop position rather than trusting the last
        // hover: a drag can end on a frame where no move was reported.
        final resolved = _resolve(details.offset);
        _clearHover();
        final edge = resolved?.edge;
        if (edge == null) {
          widget.onSwap(details.data);
        } else {
          widget.onDock(details.data, edge);
        }
      },
      builder: (context, candidates, rejected) {
        final active = _hovering && candidates.isNotEmpty;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (active)
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: widget.borderRadius,
                    child: _edge == null
                        ? _swapOverlay(tokens)
                        : _dockOverlay(tokens, _edge!),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _swapOverlay(ShellVibeTokens tokens) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.brand.withValues(alpha: 0.12),
        border: Border.all(color: tokens.brand, width: 2),
        borderRadius: widget.borderRadius,
      ),
      child: Center(
        child: _overlayBadge(tokens, LucideIcons.arrowLeftRight, 'SWAP'),
      ),
    );
  }

  /// The half of the pane the docked pane would take, so the drop shows the
  /// rectangle it is aiming at rather than only naming the side.
  Widget _dockOverlay(ShellVibeTokens tokens, PaneDockEdge edge) {
    final horizontal = edge.axis == Axis.horizontal;
    return Align(
      alignment: switch (edge) {
        PaneDockEdge.left => Alignment.centerLeft,
        PaneDockEdge.right => Alignment.centerRight,
        PaneDockEdge.top => Alignment.topCenter,
        PaneDockEdge.bottom => Alignment.bottomCenter,
      },
      child: FractionallySizedBox(
        widthFactor: horizontal ? 0.5 : 1,
        heightFactor: horizontal ? 1 : 0.5,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.brand.withValues(alpha: 0.18),
            border: Border.all(color: tokens.brand, width: 2),
          ),
          child: Center(
            child: _overlayBadge(tokens, switch (edge) {
              PaneDockEdge.left => LucideIcons.panelLeft,
              PaneDockEdge.right => LucideIcons.panelRight,
              PaneDockEdge.top => LucideIcons.panelTop,
              PaneDockEdge.bottom => LucideIcons.panelBottom,
            }, edge.name.toUpperCase()),
          ),
        ),
      ),
    );
  }

  Widget _overlayBadge(ShellVibeTokens tokens, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.terminalChrome,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: Border.all(color: tokens.brand),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tokens.brand),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: tokens.brand,
            ),
          ),
        ],
      ),
    );
  }
}
