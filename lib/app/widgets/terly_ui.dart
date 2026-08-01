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
      child: Row(
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
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 12),
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
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
