import 'package:flutter/material.dart';

import '../../../../app/widgets/shellvibe_ui.dart';

/// One Automation section laid out the way the other modules are: the header
/// and the section's content share one slab, and the detail drawer is a peer
/// of that slab rather than a column inside it.
///
/// Each section builds this itself rather than handing its drawer up: the
/// runbook drawer shows a run in progress, and that state lives with the
/// runbooks section. The header comes down instead, from `SnippetsScreen`,
/// which owns the toolbar both sections share.
class AutomationSectionLayout extends StatelessWidget {
  final Widget header;
  final Widget body;
  final Widget? drawer;

  /// Draws the slab. Off on a phone, where the list sits straight on the
  /// canvas rather than in a slab that would touch every screen edge.
  final bool framed;

  const AutomationSectionLayout({
    super.key,
    required this.header,
    required this.body,
    required this.framed,
    this.drawer,
  });

  @override
  Widget build(BuildContext context) {
    final work = Column(
      children: [
        header,
        Expanded(child: body),
      ],
    );
    return Row(
      children: [
        Expanded(
          child: framed
              ? ShellVibePanel(gradientExtent: 160, child: work)
              : work,
        ),
        ?drawer,
      ],
    );
  }
}
