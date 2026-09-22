import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/utils/platform_capabilities.dart';
import '../theme/app_theme.dart';
import '../theme/shellvibe_tokens.dart';

/// The height a control may not go below on the platform in use.
///
/// A 34px control is comfortable under a mouse and too small under a thumb, so
/// the designed height is a floor on desktop and is raised to
/// [ShellVibeTokens.touchTarget] wherever the pointer is a finger.
double shellvibeControlHeight(ShellVibeTokens tokens, double designed) =>
    isMobilePlatform ? math.max(designed, tokens.touchTarget) : designed;

/// Whether the shell shows the icon rail instead of the phone tab bar.
///
/// Width alone is not enough. A phone held sideways is 852px wide and still a
/// phone: it has no room above the fold for a vertical rail, no ⌘ to press for
/// the shortcuts the rail advertises, and a thumb rather than a pointer. Its
/// *shortest* side is what says whether two columns fit, so a touch host has
/// to clear the compact tier on that side before its width is consulted.
bool usesRailLayout(BuildContext context) {
  final tokens = ShellVibeTokens.resolve(context);
  final size = MediaQuery.sizeOf(context);
  if (isMobilePlatform && size.shortestSide < tokens.breakpointCompact) {
    return false;
  }
  if (kIsWeb) return size.width >= tokens.breakpointRailTouch;
  try {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return size.width >= tokens.breakpointRail;
    }
  } catch (_) {
    // Web and unsupported platforms fall back to the width contract.
  }
  return size.width >= tokens.breakpointRailTouch;
}

/// The night ground every Nocturne screen floats on.
///
/// Modules paint this once at their root; the slabs above it are separated by
/// [ShellVibeTokens.panelGap] whitespace, which is what makes the glow readable
/// between them.
class ShellVibeCanvas extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ShellVibeCanvas({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: tokens.canvasGradient),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A floating slab: top-lit hairline, downward gradient, drop shadow.
///
/// [gradientExtent] is the distance from the panel's top at which the gradient
/// reaches [ShellVibeTokens.surfaceLow] — anchored in pixels, not in a fraction of
/// the height, so a short panel and a tall one share the same falloff.
class ShellVibePanel extends StatelessWidget {
  final Widget child;
  final double gradientExtent;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;

  /// Overrides the hairline — used to mark a focused or errored panel.
  final Color? borderColor;

  final BorderRadius? borderRadius;

  /// Panels clip by default so inner strips can bleed to the rounded edge.
  final bool clip;

  const ShellVibePanel({
    super.key,
    required this.child,
    this.gradientExtent = 200,
    this.padding,
    this.margin,
    this.width,
    this.borderColor,
    this.borderRadius,
    this.clip = true,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final radius = borderRadius ?? BorderRadius.circular(tokens.radiusLarge);
    return Container(
      width: width,
      margin: margin,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            padding: padding,
            clipBehavior: clip ? Clip.antiAlias : Clip.none,
            decoration: BoxDecoration(
              gradient: tokens.panelGradient(
                gradientExtent: gradientExtent,
                height: constraints.maxHeight.isFinite
                    ? constraints.maxHeight
                    : null,
              ),
              borderRadius: radius,
              border: Border.all(color: borderColor ?? tokens.border),
              boxShadow: tokens.shadowPanel,
            ),
            child: child,
          );
        },
      ),
    );
  }
}

/// A slab one step above a panel — command palette, dialogs, sheets.
class ShellVibeOverlaySurface extends StatelessWidget {
  final Widget child;
  final double gradientExtent;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  const ShellVibeOverlaySurface({
    super.key,
    required this.child,
    this.gradientExtent = 200,
    this.padding,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        final stop = height == null
            ? 1.0
            : (gradientExtent / height).clamp(0.05, 1.0).toDouble();
        final shape =
            borderRadius ?? BorderRadius.circular(tokens.radiusOverlay);
        return Container(
          padding: padding,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [tokens.surfaceRaised, tokens.surfaceLow],
              stops: [0, stop],
            ),
            borderRadius: shape,
            boxShadow: tokens.shadowOverlay,
          ),
          // Drawn over the child: a clipped child covers a background border
          // along the corner arcs and breaks the outline there.
          foregroundDecoration: BoxDecoration(
            borderRadius: shape,
            border: Border.all(
              color: tokens.textPrimary.withValues(alpha: 0.09),
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// Mono type — addresses, ports, sizes, durations, shortcuts.
///
/// Nocturne gives mono a job rather than a look: if a value is machine data,
/// it is set in mono, and prose never is.
TextStyle shellvibeMono(
  BuildContext context, {
  double size = 12,
  Color? color,
  FontWeight weight = FontWeight.w400,
  double? letterSpacing,
}) {
  final tokens = ShellVibeTokens.resolve(context);
  return TextStyle(
    fontFamily: ShellVibeTokens.monoFontFamily,
    fontSize: size,
    height: 1.35,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    color: color ?? tokens.textMuted,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// The 3×20 light bar that marks a live row.
///
/// It replaces the status dot in list rows: a bar reads at a glance down a
/// column of nine hosts where a dot does not. Dots stay where space is tight —
/// tabs, tunnels, the status bar.
class ShellVibeRowIndicator extends StatelessWidget {
  final bool live;
  final double height;

  const ShellVibeRowIndicator({
    super.key,
    required this.live,
    this.height = 20,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: live ? tokens.brand : tokens.textPrimary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(2),
        boxShadow: live
            ? [
                BoxShadow(
                  color: tokens.brand.withValues(alpha: 0.7),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
    );
  }
}

/// Which of the four jobs a button is doing.
///
/// The variant is the only thing a call site chooses. Height, padding, radius,
/// icon size and every colour follow from it, so two buttons doing the same
/// job cannot drift apart by being written in two places.
enum ShellVibeButtonVariant {
  /// The one action a panel wants you to take: the raised brand gradient with
  /// its own glow. Exactly one of these belongs on a panel — it is how
  /// Nocturne marks where a screen is pointing.
  primary,

  /// Every other action that still has to be found: a hairline ring, no fill.
  secondary,

  /// An action that destroys something. Filled rather than ringed, so it
  /// cannot be mistaken at a glance for the secondary standing next to it.
  danger,

  /// An action already explained by what it sits beside — a row's own menu, a
  /// field's helper. No ring, no fill, and it only appears on hover.
  quiet,
}

/// The one button in the app.
///
/// Everything a button can be is a [variant] of this: there is no second
/// component, no size argument and no place to pass a colour. A call site
/// says what the button is for and what it says, and the rest is the token
/// contract's to decide.
///
/// Labels are required. An action with no label is a [ShellVibeIconButton],
/// which is a different affordance with different rules — it lives in a
/// toolbar, it earns its silence from its neighbours, and it carries a
/// tooltip because nothing else explains it.
class ShellVibeButton extends StatelessWidget {
  const ShellVibeButton({
    super.key,
    this.buttonKey,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = ShellVibeButtonVariant.primary,
    this.expand = false,
    this.busy = false,
  });

  const ShellVibeButton.secondary({
    super.key,
    this.buttonKey,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.busy = false,
  }) : variant = ShellVibeButtonVariant.secondary;

  const ShellVibeButton.danger({
    super.key,
    this.buttonKey,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.busy = false,
  }) : variant = ShellVibeButtonVariant.danger;

  const ShellVibeButton.quiet({
    super.key,
    this.buttonKey,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.busy = false,
  }) : variant = ShellVibeButtonVariant.quiet;

  /// What the button says. Never empty — see the class comment.
  final String label;

  /// Leading glyph, where recognising the action is faster than reading it.
  ///
  /// Reach for one on a repeated or destructive action, not on a dialog's
  /// Cancel and Save: those are read once, in place, and a tick beside "Save"
  /// says nothing the word did not.
  final IconData? icon;

  final VoidCallback? onPressed;
  final ShellVibeButtonVariant variant;

  /// Fills the row it is given instead of hugging its label.
  ///
  /// For a button in a container that is already button-width — a 284px detail
  /// drawer, a bottom sheet, one column of an even split. A button in a wide
  /// pane does not want this: a 900px-wide "Lock Vault Now" is a banner, not a
  /// button, and that is what the settings screen looked like before the wrap
  /// was taken off it.
  final bool expand;

  /// Swaps the label for a spinner and stops accepting presses, for an action
  /// that has been started and has not come back.
  final bool busy;

  /// Key on the tappable element itself, for tests that press the button.
  final Key? buttonKey;

  /// The same button, widened to fill its row.
  ///
  /// For [adaptiveDialogActions], which stacks a footer under a thumb and has
  /// to widen what it stacks without the call site knowing it happened.
  ShellVibeButton filling() => ShellVibeButton(
    key: key,
    buttonKey: buttonKey,
    label: label,
    icon: icon,
    onPressed: onPressed,
    variant: variant,
    expand: true,
    busy: busy,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final radius = BorderRadius.circular(tokens.radiusMedium);
    final enabled = onPressed != null && !busy;
    final foreground = _foreground(tokens);

    // Disabled is drawn once, here. A button that only stops responding looks
    // identical to one that is working, which is how a stuck form reads as a
    // broken app.
    final opacity = enabled ? 1.0 : 0.45;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Opacity(
        opacity: opacity,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: buttonKey,
            onTap: enabled ? onPressed : null,
            borderRadius: radius,
            child: Container(
              constraints: BoxConstraints(
                minHeight: shellvibeControlHeight(tokens, tokens.controlHeight),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: _decoration(tokens, radius),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(foreground),
                      ),
                    )
                  else ...[
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: foreground),
                      const SizedBox(width: 8),
                    ],
                    // Flexible, not Expanded: the button still hugs its label
                    // when it is free to, and gives up width only when the
                    // row it is in has none left.
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: foreground,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _foreground(ShellVibeTokens tokens) {
    switch (variant) {
      case ShellVibeButtonVariant.primary:
        return tokens.brandInk;
      case ShellVibeButtonVariant.danger:
        return AppTheme.legibleInk(tokens.danger, tokens);
      case ShellVibeButtonVariant.secondary:
      case ShellVibeButtonVariant.quiet:
        return tokens.textSecondary;
    }
  }

  BoxDecoration _decoration(ShellVibeTokens tokens, BorderRadius radius) {
    switch (variant) {
      case ShellVibeButtonVariant.primary:
        return BoxDecoration(
          gradient: tokens.brandGradient,
          borderRadius: radius,
          boxShadow: tokens.shadowBrand,
        );
      case ShellVibeButtonVariant.danger:
        return BoxDecoration(color: tokens.danger, borderRadius: radius);
      case ShellVibeButtonVariant.secondary:
        return BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: tokens.textPrimary.withValues(alpha: 0.07)),
        );
      case ShellVibeButtonVariant.quiet:
        return BoxDecoration(borderRadius: radius);
    }
  }
}

/// A toolbar action with no room for a label.
///
/// Separate from [ShellVibeButton] because the rules are different, not
/// because the drawing is: it is square rather than padded to a label, and
/// the [tooltip] is required, since a glyph with no tooltip is a guess.
class ShellVibeIconButton extends StatelessWidget {
  const ShellVibeIconButton({
    super.key,
    this.buttonKey,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.danger = false,
    this.ringed = false,
    this.active = false,
  });

  final IconData icon;

  /// What the glyph means, in words. Required — see the class comment.
  final String tooltip;

  final VoidCallback? onPressed;

  /// Tints the glyph for an action that destroys something.
  final bool danger;

  /// Draws the hairline ring a toolbar uses to separate a control from the
  /// slab behind it. Off by default: a glyph in a row of glyphs needs no ring,
  /// and a ring around each of them is a grid.
  final bool ringed;

  /// Marks a toggle that is currently on, in the brand colour.
  final bool active;

  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final enabled = onPressed != null;
    final side = shellvibeControlHeight(tokens, tokens.controlHeight);
    final radius = BorderRadius.circular(tokens.radiusMedium);
    final foreground = danger
        ? tokens.danger
        : active
        ? tokens.brand
        : tokens.textMuted;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        toggled: active,
        label: tooltip,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.45,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: buttonKey,
              onTap: onPressed,
              borderRadius: radius,
              child: Container(
                width: side,
                height: side,
                alignment: Alignment.center,
                decoration: ringed
                    ? BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(
                          color: tokens.textPrimary.withValues(alpha: 0.07),
                        ),
                      )
                    : null,
                child: Icon(icon, size: 16, color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A `label → value` line in a detail panel: sans label, mono value.
class ShellVibeDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final double labelWidth;

  const ShellVibeDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = 88,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label.toLowerCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: tokens.textSubtle,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: shellvibeMono(context, color: tokens.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The muted strip Nocturne uses to explain a screen's rules in place.
class ShellVibeInfoNote extends StatelessWidget {
  final String message;
  final IconData icon;
  final Widget? trailing;

  const ShellVibeInfoNote({
    super.key,
    required this.message,
    this.icon = LucideIcons.info,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: tokens.textSubtle),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, color: tokens.textSubtle),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

class ShellVibePageHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final List<Widget> actions;

  const ShellVibePageHeader({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackActions = constraints.maxWidth < 560;
        return Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: EdgeInsets.symmetric(
            horizontal: tokens.pagePadding,
            vertical: 12,
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
    ShellVibeTokens tokens, {
    required bool stackActions,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: tokens.brand.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
            border: Border.all(color: tokens.brand.withValues(alpha: 0.26)),
          ),
          child: Icon(icon, size: 18, color: tokens.brand),
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
          // Flexible, so the Wrap is given a width to wrap against. A Wrap
          // laid straight into a Row is measured unbounded: it puts every
          // action on one line and overflows rather than running onto a
          // second, which is invisible until an action grows a word.
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ),
        ],
      ],
    );
  }
}

class ShellVibeSearchField extends StatelessWidget {
  final Key? fieldKey;
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  /// Takes focus as soon as it is shown. For a field that opens with a panel
  /// on a phone, where it would raise the keyboard over the list it filters,
  /// leave this off.
  final bool autofocus;

  const ShellVibeSearchField({
    super.key,
    this.fieldKey,
    this.controller,
    required this.hintText,
    this.onChanged,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final height = shellvibeControlHeight(tokens, tokens.controlHeight);
    // Material sizes a prefix icon to a 48px tap target unless told
    // otherwise, which made this a 48px field with a 52px gutter in front of
    // the text on a surface designed around 34px controls.
    final iconConstraints = BoxConstraints.tightFor(width: 34, height: height);
    // The typed text matches the hint, so the field does not change size
    // under the first keystroke.
    const textStyle = TextStyle(fontSize: 13);
    return TextField(
      key: fieldKey,
      controller: controller,
      onChanged: onChanged,
      autofocus: autofocus,
      style: textStyle,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: hintText,
        isDense: true,
        constraints: BoxConstraints.tightFor(height: height),
        prefixIcon: const Icon(LucideIcons.search, size: 15),
        prefixIconConstraints: iconConstraints,
        suffixIcon: controller == null
            ? null
            : _SearchClearButton(controller: controller!, onChanged: onChanged),
        suffixIconConstraints: iconConstraints,
        contentPadding: const EdgeInsets.only(right: 12),
      ),
    );
  }
}

/// Empties a [ShellVibeSearchField], shown only while there is something to
/// empty.
class _SearchClearButton extends StatelessWidget {
  const _SearchClearButton({required this.controller, this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.text.isEmpty) return const SizedBox.shrink();
        return Semantics(
          label: 'Clear search',
          button: true,
          child: InkWell(
            key: const Key('search_field_clear'),
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              controller.clear();
              onChanged?.call('');
            },
            child: const Icon(LucideIcons.x, size: 14),
          ),
        );
      },
    );
  }
}

class ShellVibeEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<Widget> actions;

  /// Shown under the actions, set off by a rule: a shortcut list, or anything
  /// else that is a way in rather than the way in.
  final Widget? footer;

  const ShellVibeEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actions = const [],
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: tokens.brand.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: tokens.brand.withValues(alpha: 0.24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.brand.withValues(alpha: 0.12),
                      blurRadius: 60,
                    ),
                  ],
                ),
                child: Icon(icon, size: 32, color: tokens.brand),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: tokens.textMuted,
                  height: 1.55,
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
              if (footer != null) ...[
                const SizedBox(height: 28),
                Divider(color: tokens.border, height: 1),
                const SizedBox(height: 20),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum ShellVibeStatusTone { neutral, brand, info, success, warning, danger }

class ShellVibeStatusChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final ShellVibeStatusTone tone;
  final Key? chipKey;

  const ShellVibeStatusChip({
    super.key,
    this.chipKey,
    required this.label,
    this.icon,
    this.tone = ShellVibeStatusTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final color = switch (tone) {
      ShellVibeStatusTone.brand => tokens.brand,
      ShellVibeStatusTone.info => tokens.info,
      ShellVibeStatusTone.success => tokens.success,
      ShellVibeStatusTone.warning => tokens.warning,
      ShellVibeStatusTone.danger => tokens.danger,
      ShellVibeStatusTone.neutral => tokens.textMuted,
    };
    return Semantics(
      label: label,
      child: Container(
        key: chipKey,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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

/// Connection state rendered as a dot.
enum ShellVibeDotState { online, offline, error, idle }

class ShellVibeStatusDot extends StatelessWidget {
  final ShellVibeDotState state;
  final double size;

  const ShellVibeStatusDot({super.key, required this.state, this.size = 7});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final color = switch (state) {
      ShellVibeDotState.online => tokens.brand,
      ShellVibeDotState.error => tokens.danger,
      ShellVibeDotState.idle => tokens.textPrimary.withValues(alpha: 0.16),
      ShellVibeDotState.offline => Colors.transparent,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: state == ShellVibeDotState.offline
            ? Border.all(color: tokens.textMuted)
            : null,
        boxShadow: switch (state) {
          ShellVibeDotState.online => tokens.glow(tokens.brand),
          ShellVibeDotState.error => tokens.glow(tokens.danger, alpha: 0.8),
          _ => null,
        },
      ),
    );
  }
}

/// Monospace uppercase group heading used by context columns and settings.
class ShellVibeSectionLabel extends StatelessWidget {
  final String label;
  final EdgeInsetsGeometry padding;

  const ShellVibeSectionLabel({
    super.key,
    required this.label,
    this.padding = const EdgeInsets.fromLTRB(6, 12, 6, 6),
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Padding(
      padding: padding,
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.4,
          color: tokens.textSubtle,
        ),
      ),
    );
  }
}

/// Section title used to group related form fields (icon + primary-colored
/// label + trailing divider), shared across the app's form dialogs.
class ShellVibeFormSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  /// Optional control pinned to the right of the header, e.g. an action
  /// button. When present it replaces the trailing divider's tail end.
  final Widget? trailing;

  const ShellVibeFormSectionHeader({
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
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Divider(
            height: 1,
            color: ShellVibeTokens.resolve(context).border,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

/// A single entry in a context column or settings section navigation.
class ShellVibeNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;
  final Key? itemKey;

  const ShellVibeNavItem({
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
    final tokens = ShellVibeTokens.resolve(context);
    final foreground = selected ? tokens.brandSoft : tokens.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: itemKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? tokens.brand.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
            border: Border.all(
              color: selected
                  ? tokens.brand.withValues(alpha: 0.22)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: foreground,
                  ),
                ),
              ),
              if (count != null)
                Text(
                  '$count',
                  style: shellvibeMono(
                    context,
                    size: 11,
                    color: selected ? foreground : tokens.textMuted,
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
class ShellVibeContextColumn extends StatelessWidget {
  final Widget? head;
  final Widget? search;
  final List<Widget> children;

  const ShellVibeContextColumn({
    super.key,
    this.head,
    this.search,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return ShellVibePanel(
      width: tokens.contextColumnWidth,
      gradientExtent: 140,
      margin: EdgeInsets.only(right: tokens.panelGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (head != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: head,
            ),
          if (search != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: search,
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// The toolbar strip at the top of a work area (`wtop` in the wireframe).
class ShellVibeWorkToolbar extends StatelessWidget {
  final String title;
  final String? meta;
  final List<Widget> leading;
  final List<Widget> actions;

  const ShellVibeWorkToolbar({
    super.key,
    required this.title,
    this.meta,
    this.leading = const [],
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (meta != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    meta!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: shellvibeMono(
                      context,
                      size: 11,
                      color: tokens.textSubtle,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (leading.isNotEmpty || actions.isNotEmpty)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [...leading, ...actions],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The inline right-hand detail panel that replaces detail modals.
class ShellVibeDetailDrawer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const ShellVibeDetailDrawer({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return ShellVibePanel(
      width: tokens.detailDrawerWidth,
      gradientExtent: 160,
      margin: EdgeInsets.only(left: tokens.panelGap),
      padding: padding,
      child: child,
    );
  }
}

/// Bottom operations strip for terminal and SFTP.
class ShellVibeStatusBar extends StatelessWidget {
  final List<Widget> segments;
  final Widget? trailing;

  const ShellVibeStatusBar({super.key, required this.segments, this.trailing});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      height: 34,
      margin: EdgeInsets.only(top: tokens.panelGap),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tokens.railBg, tokens.surfaceLow],
        ),
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.border),
      ),
      child: DefaultTextStyle.merge(
        style: shellvibeMono(context, size: 11, color: tokens.textSubtle),
        child: Row(
          children: [
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

class ShellVibeSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool raised;
  final BorderRadius? borderRadius;
  final Color? borderColor;

  const ShellVibeSurface({
    super.key,
    required this.child,
    this.padding,
    this.raised = false,
    this.borderRadius,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: raised
              ? [tokens.surfaceRaised, tokens.surface]
              : [tokens.surface, tokens.surfaceLow],
        ),
        border: Border.all(color: borderColor ?? tokens.border),
        borderRadius: borderRadius ?? BorderRadius.circular(tokens.radiusLarge),
      ),
      child: child,
    );
  }
}

// -----------------------------------------------------------------------------
// Backwards Compatibility Aliases
// -----------------------------------------------------------------------------
