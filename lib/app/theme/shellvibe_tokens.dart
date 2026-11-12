import 'package:flutter/material.dart';

/// ShellVibe's shared visual contract — the "Nocturne" system.
///
/// Nocturne is one flat plane: panels sit flush against each other and the
/// window edge, filled with a single colour and split by one hairline. No
/// gradients, no glows, no drop shadows under anything that is not an
/// overlay.
///
/// Terminal ANSI palettes intentionally live outside this extension. The app
/// chrome keeps a stable identity while terminal sessions remain customizable.
@immutable
class ShellVibeTokens extends ThemeExtension<ShellVibeTokens> {
  /// Root ground: the caption strip and anything not inside a panel.
  final Color canvas;

  /// Panel fill.
  final Color surface;

  /// One step below [surface]: wells, inputs, inactive strips.
  final Color surfaceLow;

  /// Overlays (dialogs, palette) and active tabs.
  final Color surfaceRaised;

  /// Terminal body. Flat and opaque, a step darker than the panels so the
  /// terminal reads as its own surface.
  final Color terminalBg;

  /// Chrome strip above a terminal body (pane header, tab bar backing).
  final Color terminalChrome;

  /// Status bar and other docked strips.
  final Color railBg;

  /// The single hairline used by every panel edge and divider.
  final Color border;

  final Color textPrimary;

  /// List row names and other second-rank copy.
  final Color textSecondary;

  /// Secondary text and idle icons.
  final Color textMuted;

  /// Section labels, meta, shortcuts.
  final Color textSubtle;

  final Color brand;

  /// Bright tint of [brand], used for selected state accents and active icons.
  final Color brandBright;

  /// Soft tint of [brand], used for chips, badges and subtle highlights.
  final Color brandSoft;

  /// Text and icons drawn on top of [brand].
  final Color brandInk;

  final Color info;
  final Color success;
  final Color warning;
  final Color danger;

  /// Muted background fill for danger/error notices and disconnect banners.
  final Color dangerMutedSurface;

  /// Foreground text color for muted danger/error notices.
  final Color dangerMutedText;

  /// Border color for muted danger/error notices.
  final Color dangerMutedBorder;

  /// Drop shadow under a popover or floating menu. A night ground can take a
  /// heavier shadow than a daylight one, so the strength is a token rather
  /// than a constant baked into [shadowPanel].
  final Color shadowColor;

  /// Drop shadow under an overlay — deeper than [shadowColor].
  final Color shadowColorStrong;

  /// Chips and badges.
  final double radiusSmall;

  /// Controls, list rows, tabs.
  final double radiusMedium;

  /// Cards and terminal panes. Shell panels are square: they meet the window
  /// edge and each other.
  final double radiusLarge;

  /// Command palette and dialogs — one step above a panel.
  final double radiusOverlay;

  final double radiusPill;
  final double pagePadding;
  final double controlHeight;

  /// Whitespace between shell panels. Zero: panels sit flush and the shared
  /// [border] hairline is what separates them.
  final double panelGap;

  /// Desktop list row height. 48px is what the radius and inner padding need.
  final double rowHeight;

  /// Fixed icon rail width — the wireframe's persistent skeleton column.
  final double railWidth;

  /// Per-module context column between the rail and the work area.
  final double contextColumnWidth;

  /// Inline right-hand detail panel that replaces detail modals.
  final double detailDrawerWidth;

  /// Minimum interactive size on touch platforms.
  final double touchTarget;

  /// Below this a surface is one column: a phone, or a window narrowed to one.
  ///
  /// Deliberately the same 640 shadcn's `sm` uses, because that is the width at
  /// which its dialogs stack their actions — a layout tier the app does not get
  /// to opt out of, so its own tier had better agree with it.
  final double breakpointCompact;

  /// At and above this a module can afford its context column beside the work
  /// area. Measured on the module's own constraints, not on the screen.
  final double breakpointMedium;

  /// At and above this the inline detail drawer fits as a third column.
  final double breakpointExpanded;

  /// Screen width at which the shell swaps the phone tab bar for the rail on a
  /// desktop host. Lower than [breakpointRailTouch] because a mouse can hit the
  /// 38px rail buttons that a finger cannot.
  final double breakpointRail;

  /// Screen width at which a touch host earns the rail. Tablets clear it; a
  /// phone held sideways does not, because the shell also weighs its shortest
  /// side.
  final double breakpointRailTouch;

  final Duration motionFast;

  const ShellVibeTokens({
    required this.canvas,
    required this.surface,
    required this.surfaceLow,
    required this.surfaceRaised,
    required this.terminalBg,
    required this.terminalChrome,
    required this.railBg,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textSubtle,
    required this.brand,
    this.brandBright = const Color(0xFFF0B65A),
    this.brandSoft = const Color(0xFFF3C987),
    required this.brandInk,
    required this.info,
    required this.success,
    required this.warning,
    required this.danger,
    this.dangerMutedSurface = const Color(0xFF2A0710),
    this.dangerMutedText = const Color(0xFFFFC2CC),
    this.dangerMutedBorder = const Color(0xFFC09AA3),
    required this.shadowColor,
    required this.shadowColorStrong,
    this.radiusSmall = 5,
    this.radiusMedium = 6,
    this.radiusLarge = 12,
    this.radiusOverlay = 14,
    this.radiusPill = 999,
    this.pagePadding = 16,
    this.controlHeight = 34,
    this.panelGap = 0,
    this.rowHeight = 48,
    this.railWidth = 56,
    this.contextColumnWidth = 240,
    this.detailDrawerWidth = 284,
    this.touchTarget = 44,
    this.breakpointCompact = 640,
    this.breakpointMedium = 900,
    this.breakpointExpanded = 1180,
    this.breakpointRail = 720,
    this.breakpointRailTouch = 800,
    this.motionFast = const Duration(milliseconds: 120),
  });

  static const dark = ShellVibeTokens(
    canvas: Color(0xFF141414),
    surface: Color(0xFF141414),
    surfaceLow: Color(0xFF101010),
    surfaceRaised: Color(0xFF1E1E1E),
    terminalBg: Color(0xFF101010),
    terminalChrome: Color(0xFF181818),
    railBg: Color(0xFF181818),
    // rgba(255,255,255,0.09): reads as #2B2B2B on the ground, and still
    // separates two panels that share it.
    border: Color(0x17FFFFFF),
    textPrimary: Color(0xFFEDEDEA),
    textSecondary: Color(0xFFD6D6D2),
    textMuted: Color(0xFF9A9A95),
    textSubtle: Color(0xFF6E6E69),
    brand: Color(0xFFE5A23C),
    brandInk: Color(0xFF17130A),
    info: Color(0xFF7FAEE6),
    success: Color(0xFF6FBF73),
    warning: Color(0xFFE3C179),
    danger: Color(0xFFEE8A8A),
    shadowColor: Color(0x66000000),
    shadowColorStrong: Color(0x8C000000),
  );

  /// Daylight counterpart: the same roles and radii on a white plane.
  static const light = ShellVibeTokens(
    canvas: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceLow: Color(0xFFF6F6F4),
    surfaceRaised: Color(0xFFFFFFFF),
    // Daylight has its own terminal chrome; the dark values would paint a
    // near-black pane header on a white app.
    terminalBg: Color(0xFFF6F6F4),
    terminalChrome: Color(0xFFEDEDEA),
    railBg: Color(0xFFF6F6F4),
    border: Color(0x1A000000),
    textPrimary: Color(0xFF1A1A18),
    textSecondary: Color(0xFF33332F),
    textMuted: Color(0xFF63635D),
    textSubtle: Color(0xFF8C8C85),
    brand: Color(0xFF9A5A00),
    brandBright: Color(0xFF7F4A00),
    brandSoft: Color(0xFFB86E00),
    brandInk: Color(0xFFFFFFFF),
    info: Color(0xFF1D5FD1),
    success: Color(0xFF1E7A35),
    warning: Color(0xFFA15C00),
    danger: Color(0xFFB4232F),
    dangerMutedSurface: Color(0xFFFFEBEF),
    dangerMutedText: Color(0xFF9F1239),
    dangerMutedBorder: Color(0xFFFCA5A5),
    shadowColor: Color(0x14000000),
    shadowColorStrong: Color(0x24000000),
  );

  static ShellVibeTokens resolve(BuildContext context) {
    return Theme.of(context).extension<ShellVibeTokens>() ??
        (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

  /// Behind a selected row, chip, tab or list item. Selection is a state,
  /// not the brand, so it is drawn in the text colour rather than the accent.
  Color get selectedFill => textPrimary.withValues(alpha: 0.09);

  /// Under a popover or floating menu. Shell panels have no shadow.
  List<BoxShadow> get shadowPanel => [
    BoxShadow(color: shadowColor, blurRadius: 16, offset: const Offset(0, 6)),
  ];

  /// Under the command palette and dialogs.
  List<BoxShadow> get shadowOverlay => [
    BoxShadow(
      color: shadowColorStrong,
      blurRadius: 40,
      offset: const Offset(0, 16),
    ),
  ];

  /// Interface family for everything that is not machine data.
  ///
  /// Bundled with the app, so a first launch without a network still renders
  /// the shell in its own face rather than the platform's.
  static const String uiFontFamily = 'Inter Tight';

  /// Mono family for addresses, ports, sizes, durations and shortcuts.
  ///
  /// Bundled with the app, so it resolves offline — unlike the design's web
  /// JetBrains Mono, which this file ships as its Nerd Font sibling.
  static const String monoFontFamily = 'JetBrainsMono Nerd Font Mono';

  @override
  ShellVibeTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceLow,
    Color? surfaceRaised,
    Color? terminalBg,
    Color? terminalChrome,
    Color? railBg,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textSubtle,
    Color? brand,
    Color? brandBright,
    Color? brandSoft,
    Color? brandInk,
    Color? info,
    Color? success,
    Color? warning,
    Color? danger,
    Color? dangerMutedSurface,
    Color? dangerMutedText,
    Color? dangerMutedBorder,
    Color? shadowColor,
    Color? shadowColorStrong,
    double? radiusSmall,
    double? radiusMedium,
    double? radiusLarge,
    double? radiusOverlay,
    double? radiusPill,
    double? pagePadding,
    double? controlHeight,
    double? panelGap,
    double? rowHeight,
    double? railWidth,
    double? contextColumnWidth,
    double? detailDrawerWidth,
    double? touchTarget,
    double? breakpointCompact,
    double? breakpointMedium,
    double? breakpointExpanded,
    double? breakpointRail,
    double? breakpointRailTouch,
    Duration? motionFast,
  }) {
    return ShellVibeTokens(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceLow: surfaceLow ?? this.surfaceLow,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      terminalBg: terminalBg ?? this.terminalBg,
      terminalChrome: terminalChrome ?? this.terminalChrome,
      railBg: railBg ?? this.railBg,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textSubtle: textSubtle ?? this.textSubtle,
      brand: brand ?? this.brand,
      brandBright: brandBright ?? this.brandBright,
      brandSoft: brandSoft ?? this.brandSoft,
      brandInk: brandInk ?? this.brandInk,
      info: info ?? this.info,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      dangerMutedSurface: dangerMutedSurface ?? this.dangerMutedSurface,
      dangerMutedText: dangerMutedText ?? this.dangerMutedText,
      dangerMutedBorder: dangerMutedBorder ?? this.dangerMutedBorder,
      shadowColor: shadowColor ?? this.shadowColor,
      shadowColorStrong: shadowColorStrong ?? this.shadowColorStrong,
      radiusSmall: radiusSmall ?? this.radiusSmall,
      radiusMedium: radiusMedium ?? this.radiusMedium,
      radiusLarge: radiusLarge ?? this.radiusLarge,
      radiusOverlay: radiusOverlay ?? this.radiusOverlay,
      radiusPill: radiusPill ?? this.radiusPill,
      pagePadding: pagePadding ?? this.pagePadding,
      controlHeight: controlHeight ?? this.controlHeight,
      panelGap: panelGap ?? this.panelGap,
      rowHeight: rowHeight ?? this.rowHeight,
      railWidth: railWidth ?? this.railWidth,
      contextColumnWidth: contextColumnWidth ?? this.contextColumnWidth,
      detailDrawerWidth: detailDrawerWidth ?? this.detailDrawerWidth,
      touchTarget: touchTarget ?? this.touchTarget,
      breakpointCompact: breakpointCompact ?? this.breakpointCompact,
      breakpointMedium: breakpointMedium ?? this.breakpointMedium,
      breakpointExpanded: breakpointExpanded ?? this.breakpointExpanded,
      breakpointRail: breakpointRail ?? this.breakpointRail,
      breakpointRailTouch: breakpointRailTouch ?? this.breakpointRailTouch,
      motionFast: motionFast ?? this.motionFast,
    );
  }

  @override
  ShellVibeTokens lerp(covariant ShellVibeTokens? other, double t) {
    if (other == null) return this;
    return ShellVibeTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceLow: Color.lerp(surfaceLow, other.surfaceLow, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      terminalBg: Color.lerp(terminalBg, other.terminalBg, t)!,
      terminalChrome: Color.lerp(terminalChrome, other.terminalChrome, t)!,
      railBg: Color.lerp(railBg, other.railBg, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textSubtle: Color.lerp(textSubtle, other.textSubtle, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandBright: Color.lerp(brandBright, other.brandBright, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      brandInk: Color.lerp(brandInk, other.brandInk, t)!,
      info: Color.lerp(info, other.info, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerMutedSurface: Color.lerp(
        dangerMutedSurface,
        other.dangerMutedSurface,
        t,
      )!,
      dangerMutedText: Color.lerp(dangerMutedText, other.dangerMutedText, t)!,
      dangerMutedBorder: Color.lerp(
        dangerMutedBorder,
        other.dangerMutedBorder,
        t,
      )!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
      shadowColorStrong: Color.lerp(
        shadowColorStrong,
        other.shadowColorStrong,
        t,
      )!,
      radiusSmall: _lerpDouble(radiusSmall, other.radiusSmall, t),
      radiusMedium: _lerpDouble(radiusMedium, other.radiusMedium, t),
      radiusLarge: _lerpDouble(radiusLarge, other.radiusLarge, t),
      radiusOverlay: _lerpDouble(radiusOverlay, other.radiusOverlay, t),
      radiusPill: _lerpDouble(radiusPill, other.radiusPill, t),
      pagePadding: _lerpDouble(pagePadding, other.pagePadding, t),
      controlHeight: _lerpDouble(controlHeight, other.controlHeight, t),
      panelGap: _lerpDouble(panelGap, other.panelGap, t),
      rowHeight: _lerpDouble(rowHeight, other.rowHeight, t),
      railWidth: _lerpDouble(railWidth, other.railWidth, t),
      contextColumnWidth: _lerpDouble(
        contextColumnWidth,
        other.contextColumnWidth,
        t,
      ),
      detailDrawerWidth: _lerpDouble(
        detailDrawerWidth,
        other.detailDrawerWidth,
        t,
      ),
      touchTarget: _lerpDouble(touchTarget, other.touchTarget, t),
      // Breakpoints are layout thresholds, not paint: crossfading them would
      // move the tier boundary through the middle of a theme animation.
      breakpointCompact: t < 0.5 ? breakpointCompact : other.breakpointCompact,
      breakpointMedium: t < 0.5 ? breakpointMedium : other.breakpointMedium,
      breakpointExpanded: t < 0.5
          ? breakpointExpanded
          : other.breakpointExpanded,
      breakpointRail: t < 0.5 ? breakpointRail : other.breakpointRail,
      breakpointRailTouch: t < 0.5
          ? breakpointRailTouch
          : other.breakpointRailTouch,
      motionFast: t < 0.5 ? motionFast : other.motionFast,
    );
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
