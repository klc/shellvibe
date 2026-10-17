import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';

/// The pieces the snippet and runbook lists are both built from: the column
/// header, the dense row, the detail panel's head, the narrow-width sheet and
/// the delete confirmation. The two halves of the automation library read the
/// same because they share these, not because they were copied.

/// Width of a row's trailing controls: [actionCount] icon buttons plus the
/// overflow menu, each one control height square.
///
/// That height is 34px under a pointer and the touch target on a touch host,
/// so a fixed width measured on desktop overflowed a phone or iPad row by the
/// difference. The menu trigger is sized by [shellvibeMenuTriggerStyle] so it
/// counts as one of them.
double automationActionsWidth(ShellVibeTokens tokens, int actionCount) =>
    (actionCount + 1) * shellvibeControlHeight(tokens, tokens.controlHeight);

/// Column labels over a list; the third column drops out when compact.
class AutomationListHeader extends StatelessWidget {
  final List<String> labels;
  final List<int> columnFlex;
  final bool compact;
  final int actionCount;

  const AutomationListHeader({
    super.key,
    required this.labels,
    required this.columnFlex,
    required this.compact,
    required this.actionCount,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontSize: 10,
      letterSpacing: 0.8,
      color: tokens.textMuted,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            if (i < 2 || !compact)
              Expanded(
                flex: columnFlex[i],
                child: Text(labels[i], style: style, maxLines: 1),
              ),
          SizedBox(width: automationActionsWidth(tokens, actionCount)),
        ],
      ),
    );
  }
}

/// Single-line dense row: title, subtitle, an optional third column that
/// drops out when compact, then [actions] and an overflow menu.
class AutomationRow extends StatelessWidget {
  /// Key of the tappable surface, which tests reach for.
  final Key tileKey;
  final String title;
  final String subtitle;

  /// Monospace subtitle, for a command preview.
  final bool monoSubtitle;
  final Widget? third;
  final List<int> columnFlex;
  final bool compact;
  final bool selected;
  final String semanticsLabel;
  final VoidCallback onSelect;

  /// Icon buttons before the menu; sized one control height each.
  final List<Widget> actions;
  final String menuTooltip;
  final List<PopupMenuEntry<String>> menuItems;
  final ValueChanged<String> onMenuSelected;

  const AutomationRow({
    super.key,
    required this.tileKey,
    required this.title,
    required this.subtitle,
    this.monoSubtitle = false,
    this.third,
    required this.columnFlex,
    required this.compact,
    required this.selected,
    required this.semanticsLabel,
    required this.onSelect,
    required this.actions,
    required this.menuTooltip,
    required this.menuItems,
    required this.onMenuSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: tokens.textMuted,
      fontFamily: monoSubtitle ? 'monospace' : null,
      fontSize: 12,
    );

    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      child: InkWell(
        key: tileKey,
        onTap: onSelect,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          constraints: const BoxConstraints(minHeight: 42),
          decoration: BoxDecoration(
            color: selected
                ? tokens.textPrimary.withValues(alpha: 0.06)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(color: tokens.border),
              left: BorderSide(
                color: selected ? tokens.brand : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: columnFlex[0],
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                flex: columnFlex[1],
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: subtitleStyle,
                ),
              ),
              if (!compact && third != null)
                Expanded(flex: columnFlex[2], child: third!),
              SizedBox(
                width: automationActionsWidth(tokens, actions.length),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ...actions,
                    PopupMenuButton<String>(
                      tooltip: menuTooltip,
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      style: shellvibeMenuTriggerStyle(tokens),
                      icon: const Icon(LucideIcons.ellipsis, size: 16),
                      onSelected: onMenuSelected,
                      itemBuilder: (context) => menuItems,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An icon-and-label entry of a row's overflow menu.
PopupMenuItem<String> automationMenuItem({
  Key? key,
  required String value,
  required IconData icon,
  required String label,
  Color? color,
}) => PopupMenuItem(
  key: key,
  value: value,
  child: Row(
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 8),
      // Flexible: the menu is as wide as its widest item, and the long one
      // must not push past it.
      Flexible(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: color == null ? null : TextStyle(color: color),
        ),
      ),
    ],
  ),
);

/// The top of a detail panel: title, description, close and tags.
class AutomationDetailHeader extends StatelessWidget {
  final String title;
  final String? description;
  final List<String> tags;
  final VoidCallback onClose;

  const AutomationDetailHeader({
    super.key,
    required this.title,
    this.description,
    required this.tags,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (description?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 2),
                    Text(
                      description!,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: tokens.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            ShellVibeIconButton(
              icon: LucideIcons.x,
              tooltip: 'Close details',
              onPressed: onClose,
            ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final tag in tags) ShellVibeStatusChip(label: '#$tag'),
            ],
          ),
        ],
      ],
    );
  }
}

/// The narrow-width form of the detail drawer. [builder] gets the sheet's own
/// context, so its actions can close the sheet before they act.
void showAutomationDetailSheet(
  BuildContext context,
  Widget Function(BuildContext sheetContext) builder,
) {
  final tokens = ShellVibeTokens.resolve(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: tokens.surface,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.72,
        child: builder(sheetContext),
      ),
    ),
  );
}

/// "Delete Snippet / Runbook?" — true when confirmed.
Future<bool> confirmAutomationDelete(
  BuildContext context, {
  required String what,
  required String name,
}) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => ShadDialog.alert(
      title: Text('Delete $what'),
      description: Text('Are you sure you want to delete "$name"?'),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        ShellVibeButton.danger(
          label: 'Delete',
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
    ),
  );
  return confirm == true;
}
