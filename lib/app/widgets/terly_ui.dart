import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme/terly_tokens.dart';

class TerlyPageHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final List<Widget> actions;

  const TerlyPageHeader({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this the title row and the actions cannot share a line without
        // clipping one of them, so the actions wrap underneath.
        final stackActions = constraints.maxWidth < 560;
        return Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: EdgeInsets.symmetric(
            horizontal: tokens.pagePadding,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: tokens.canvas,
            border: Border(bottom: BorderSide(color: tokens.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTitleRow(context, tokens, stackActions: stackActions),
              if (stackActions && actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTitleRow(
    BuildContext context,
    TerlyTokens tokens, {
    required bool stackActions,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: tokens.brand.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
            border: Border.all(color: tokens.brand.withValues(alpha: 0.24)),
          ),
          child: Icon(icon, size: 17, color: tokens.brand),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 2),
                Text(
                  description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                ),
              ],
            ],
          ),
        ),
        if (!stackActions && actions.isNotEmpty) ...[
          const SizedBox(width: 12),
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      ],
    );
  }
}

class TerlySearchField extends StatelessWidget {
  final Key? fieldKey;
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  const TerlySearchField({
    super.key,
    this.fieldKey,
    this.controller,
    required this.hintText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return SizedBox(
      height: tokens.controlHeight,
      child: TextField(
        key: fieldKey,
        controller: controller,
        onChanged: onChanged,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(LucideIcons.search, size: 17),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
        ),
      ),
    );
  }
}

class TerlyEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<Widget> actions;

  const TerlyEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(tokens.radiusLarge),
                  border: Border.all(color: tokens.border),
                ),
                child: Icon(icon, size: 24, color: tokens.brand),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textMuted,
                  height: 1.45,
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum TerlyStatusTone { neutral, brand, info, success, warning, danger }

class TerlyStatusChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final TerlyStatusTone tone;
  final Key? chipKey;

  const TerlyStatusChip({
    super.key,
    this.chipKey,
    required this.label,
    this.icon,
    this.tone = TerlyStatusTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    final color = switch (tone) {
      TerlyStatusTone.brand => tokens.brand,
      TerlyStatusTone.info => tokens.info,
      TerlyStatusTone.success => tokens.success,
      TerlyStatusTone.warning => tokens.warning,
      TerlyStatusTone.danger => tokens.danger,
      TerlyStatusTone.neutral => tokens.textMuted,
    };
    return Semantics(
      label: label,
      child: Container(
        key: chipKey,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(tokens.radiusPill),
          border: Border.all(color: color.withValues(alpha: 0.26)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Connection state rendered as a dot.
///
/// The wireframe pairs this with text on every surface it appears — the dot
/// alone is never the only carrier of the state, so colour-blind users keep
/// the information.
enum TerlyDotState { online, offline, error, idle }

class TerlyStatusDot extends StatelessWidget {
  final TerlyDotState state;
  final double size;

  const TerlyStatusDot({super.key, required this.state, this.size = 7});

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    final color = switch (state) {
      TerlyDotState.online => tokens.brand,
      TerlyDotState.error => tokens.danger,
      TerlyDotState.idle => tokens.textMuted,
      TerlyDotState.offline => Colors.transparent,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: state == TerlyDotState.offline
            ? Border.all(color: tokens.textMuted)
            : null,
        boxShadow: state == TerlyDotState.online
            ? [
                BoxShadow(
                  color: tokens.brand.withValues(alpha: 0.16),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
    );
  }
}

/// Monospace uppercase group heading used by context columns and settings.
class TerlySectionLabel extends StatelessWidget {
  final String label;
  final EdgeInsetsGeometry padding;

  const TerlySectionLabel({
    super.key,
    required this.label,
    this.padding = const EdgeInsets.fromLTRB(6, 12, 6, 6),
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return Padding(
      padding: padding,
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 10,
          letterSpacing: 0.8,
          color: tokens.textMuted,
        ),
      ),
    );
  }
}

/// Section title used to group related form fields (icon + primary-colored
/// label + trailing divider), shared across the app's form dialogs.
class TerlyFormSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  /// Optional control pinned to the right of the header, e.g. an action
  /// button. When present it replaces the trailing divider's tail end.
  final Widget? trailing;

  const TerlyFormSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

/// A single entry in a context column or settings section navigation.
class TerlyNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;
  final Key? itemKey;

  const TerlyNavItem({
    super.key,
    this.itemKey,
    required this.icon,
    required this.label,
    this.count,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    final foreground = selected ? tokens.textPrimary : tokens.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: itemKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? tokens.textPrimary.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(tokens.radiusSmall),
            border: Border(
              left: BorderSide(
                color: selected ? tokens.brand : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 13, color: foreground),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: foreground),
                ),
              ),
              if (count != null)
                Text(
                  '$count',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 232px per-module column that sits between the rail and the work area.
///
/// Each module owns its own column contents; the shell deliberately does not
/// host it, so switching modules only swaps the middle of the skeleton.
class TerlyContextColumn extends StatelessWidget {
  final Widget? head;
  final Widget? search;
  final List<Widget> children;

  const TerlyContextColumn({
    super.key,
    this.head,
    this.search,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return Container(
      width: tokens.contextColumnWidth,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(right: BorderSide(color: tokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (head != null)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: tokens.border)),
              ),
              child: head,
            ),
          if (search != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: search,
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// The toolbar strip at the top of a work area (`wtop` in the wireframe).
class TerlyWorkToolbar extends StatelessWidget {
  final String title;
  final String? meta;
  final List<Widget> leading;
  final List<Widget> actions;

  const TerlyWorkToolbar({
    super.key,
    required this.title,
    this.meta,
    this.leading = const [],
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (meta != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                meta!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
          for (final widget in leading) ...[const SizedBox(width: 8), widget],
          const Spacer(),
          for (final widget in actions) ...[const SizedBox(width: 6), widget],
        ],
      ),
    );
  }
}

/// The inline right-hand detail panel that replaces detail modals.
///
/// Keeping it inline is the point: list selection and filter context stay on
/// screen while the detail is read.
class TerlyDetailDrawer extends StatelessWidget {
  final Widget child;

  const TerlyDetailDrawer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return Container(
      width: tokens.detailDrawerWidth,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(left: BorderSide(color: tokens.border)),
      ),
      child: child,
    );
  }
}

/// Bottom operations strip for terminal and SFTP.
///
/// Carries debugging data (connection state, geometry, active tunnels) rather
/// than decoration, so it is intentionally absent from the other modules.
///
/// [segments] are laid out inside a horizontal scroll view, so each one must
/// size itself: passing a `Flexible` or `Expanded` segment throws. Bound long
/// text with a `ConstrainedBox` instead.
class TerlyStatusBar extends StatelessWidget {
  final List<Widget> segments;
  final Widget? trailing;

  const TerlyStatusBar({super.key, required this.segments, this.trailing});

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          fontSize: 11,
          color: tokens.textMuted,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        child: Row(
          children: [
            // Segments scroll rather than overflow: a narrow window must still
            // show the leading connection state instead of throwing away the
            // whole strip.
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: false,
                child: Row(
                  children: [
                    for (var i = 0; i < segments.length; i++) ...[
                      if (i > 0)
                        Container(
                          width: 1,
                          height: 11,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          color: tokens.border,
                        ),
                      segments[i],
                    ],
                  ],
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

class TerlySurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool raised;
  final BorderRadius? borderRadius;
  final Color? borderColor;

  const TerlySurface({
    super.key,
    required this.child,
    this.padding,
    this.raised = false,
    this.borderRadius,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: raised ? tokens.surfaceRaised : tokens.surface,
        border: Border.all(color: borderColor ?? tokens.border),
        borderRadius: borderRadius ?? BorderRadius.circular(tokens.radiusLarge),
      ),
      child: child,
    );
  }
}
