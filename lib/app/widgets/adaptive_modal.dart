import 'package:flutter/material.dart';

import '../theme/shellvibe_tokens.dart';
import 'shellvibe_ui.dart';

/// Where a modal belongs on this host.
///
/// A bottom sheet is a thumb affordance: it is reachable, it is dismissed by a
/// drag, and it takes the full width because a phone has no other width. None
/// of that is true with a pointer and a 1400px window, where the same sheet
/// reads as a phone control that wandered onto a desktop. This is the one
/// place that decides which form a modal takes, so every call site gets the
/// same answer and a new modal cannot pick the wrong one by accident.
///
/// The policy mirrors [usesRailLayout]: a touch host in landscape is still a
/// phone, so the shortest side has to clear the compact tier before width is
/// consulted at all.
bool usesDesktopModals(BuildContext context) => usesRailLayout(context);

/// A dialog footer's actions, laid out for the pointer or for the thumb.
///
/// Under a pointer the footer is a right-aligned row of buttons that hug their
/// labels. Under a thumb there is no room for that, so the buttons stack and
/// fill the width — and the order flips, because the affirmative action is
/// written last in a row and has to end up on top of a stack, where the thumb
/// already is.
///
/// Pass the actions in reading order for the row: cancel first, confirm last.
List<Widget> adaptiveDialogActions(
  BuildContext context,
  List<ShellVibeButton> actions,
) {
  if (usesDesktopModals(context)) return actions;
  return actions.reversed.map((a) => a.filling()).toList();
}

/// The axis [adaptiveDialogActions] laid its result out on.
///
/// Handed to `ShadDialog.actionsAxis`, which is what actually does the
/// stacking; the list alone cannot say which way it wants to run.
Axis adaptiveDialogActionsAxis(BuildContext context) =>
    usesDesktopModals(context) ? Axis.horizontal : Axis.vertical;

/// One row of [showAdaptiveActionMenu].
class AdaptiveMenuAction<T> {
  const AdaptiveMenuAction({
    required this.value,
    required this.icon,
    required this.label,
    this.itemKey,
  });

  /// Returned from the menu future when this row is chosen.
  final T value;
  final IconData icon;
  final String label;

  /// Carried onto whichever widget the row becomes, so a test finds the same
  /// key in both the desktop menu and the phone sheet.
  final Key? itemKey;
}

/// A short list of actions: "new tab", "split this way".
///
/// On desktop this is a dropdown anchored to [context]'s widget — the button
/// that opened it — because that is where a pointer already is and a sheet
/// sliding up from the bottom of a large window is a long way from the click.
/// On a phone it stays a bottom sheet.
Future<T?> showAdaptiveActionMenu<T>({
  required BuildContext context,
  required List<AdaptiveMenuAction<T>> actions,
}) {
  final tokens = ShellVibeTokens.resolve(context);

  if (!usesDesktopModals(context)) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      backgroundColor: tokens.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in actions)
              ListTile(
                key: action.itemKey,
                leading: Icon(action.icon, size: 18),
                title: Text(action.label),
                onTap: () => Navigator.of(sheetContext).pop(action.value),
              ),
          ],
        ),
      ),
    );
  }

  final anchor = _anchorRect(context);
  return showMenu<T>(
    context: context,
    position: anchor,
    color: tokens.surfaceRaised,
    surfaceTintColor: Colors.transparent,
    shadowColor: tokens.shadowColorStrong,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      side: BorderSide(color: tokens.border),
    ),
    items: [
      for (final action in actions)
        PopupMenuItem<T>(
          key: action.itemKey,
          value: action.value,
          height: tokens.rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(action.icon, size: 16, color: tokens.textSecondary),
              const SizedBox(width: 10),
              // The menu is capped at Material's max width, and a long label
              // ("Show Device Link QR") reaches it on a narrow window.
              Flexible(
                child: Text(
                  action.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: tokens.textPrimary),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// A modal with real content in it: a host picker, a transfer queue, a compose
/// box. Desktop gets a centred panel sized to its content; a phone gets the
/// bottom sheet it had.
///
/// [desktopWidth] and [desktopHeight] size the panel. A null height lets the
/// panel wrap its child, which is what a short list wants; a list that can
/// grow past the window should pass one.
Future<T?> showAdaptivePanel<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  double desktopWidth = 460,
  double? desktopHeight,
  bool isScrollControlled = false,
  bool transparentSheetBackground = false,
}) {
  final tokens = ShellVibeTokens.resolve(context);

  if (!usesDesktopModals(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      showDragHandle: !transparentSheetBackground,
      backgroundColor: transparentSheetBackground
          ? Colors.transparent
          : tokens.surface,
      builder: builder,
    );
  }

  return showDialog<T>(
    context: context,
    builder: (dialogContext) {
      final maxHeight = MediaQuery.sizeOf(dialogContext).height * 0.72;
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: desktopWidth,
            maxHeight: desktopHeight ?? maxHeight,
          ),
          child: ShellVibeOverlaySurface(
            // The dialog route paints no Material of its own here, and the
            // rows inside these panels are Material widgets (ListTile, InkWell)
            // that need one above them.
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null) _AdaptivePanelHeader(title: title),
                  Flexible(child: builder(dialogContext)),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _AdaptivePanelHeader extends StatelessWidget {
  const _AdaptivePanelHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
              ),
            ),
          ),
          ShellVibeIconButton(
            icon: Icons.close,
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/// The screen rectangle of [context]'s widget, as [showMenu] wants it.
///
/// Falls back to the top-left of the screen when the context has no box yet,
/// which only happens if a caller passes a context that never laid out.
RelativeRect _anchorRect(BuildContext context) {
  final overlay = Overlay.of(context).context.findRenderObject();
  final button = context.findRenderObject();
  if (button is! RenderBox || overlay is! RenderBox) {
    return const RelativeRect.fromLTRB(0, 0, 0, 0);
  }
  final origin = button.localToGlobal(Offset.zero, ancestor: overlay);
  return RelativeRect.fromLTRB(
    origin.dx,
    origin.dy + button.size.height + 4,
    overlay.size.width - origin.dx - button.size.width,
    0,
  );
}
