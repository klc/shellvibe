import 'package:flutter/material.dart';

/// ShellVibe's shared visual contract — the "Nocturne" system.
///
/// Nocturne treats the shell as slabs floating on a night ground rather than
/// one flat plane: panels carry a top-lit hairline, a downward gradient and a
/// drop shadow, and they are separated by [panelGap] whitespace instead of
/// divider rules.
///
/// Terminal ANSI palettes intentionally live outside this extension. The app
/// chrome keeps a stable identity while terminal sessions remain customizable.
@immutable
class ShellVibeTokens extends ThemeExtension<ShellVibeTokens> {
  /// Root ground behind every panel. Paired with [canvasGlow] by [canvasGradient].
  final Color canvas;

  /// Warm lift painted into the top-left of the canvas.
  final Color canvasGlow;

  /// Top of a floating panel's gradient.
  final Color surface;

  /// Bottom of a floating panel's gradient.
  final Color surfaceLow;

  /// Overlays (dialogs, palette) and active tabs.
  final Color surfaceRaised;

  /// Terminal body. Deliberately flat and opaque — readability is never traded
  /// for the panel gradient.
  final Color terminalBg;

  /// Chrome strip above a terminal body (pane header, tab bar backing).
  final Color terminalChrome;

  /// Top of the navigation rail's gradient.
  final Color railBg;

  /// The single hairline used by every panel edge.
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

  /// Text and icons drawn on top of [brand] or the brand gradient.
  final Color brandInk;

  /// Top stop of the raised brand gradient used by primary actions.
  final Color brandGradientTop;

  /// Bottom stop of the raised brand gradient used by primary actions.
  final Color brandGradientBottom;

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

  /// Drop shadow under a floating panel. A night ground can take a heavy
  /// shadow; a daylight one cannot, so the strength is a token rather than a
  /// constant baked into [shadowPanel].
  final Color shadowColor;

  /// Drop shadow under an overlay — deeper than [shadowColor].
  final Color shadowColorStrong;

  /// Chips and badges.
  final double radiusSmall;

  /// Controls, list rows, tabs.
  final double radiusMedium;

  /// Floating panels, rail, terminal.
  final double radiusLarge;

  /// Command palette and dialogs — one step above a panel.
  final double radiusOverlay;

  final double radiusPill;
  final double pagePadding;
  final double controlHeight;

  /// Whitespace between floating slabs. Nocturne separates panels with this
  /// gap instead of a divider line.
  final double panelGap;

  /// Desktop list row height. 48px is what the radius and inner padding need.
  final double rowHeight;

  /// Fixed icon rail width — the wireframe's persistent skeleton column.
  final double railWidth;

  /// Per-module context column between the rail and the work area.
  final double contextColumnWidth;

  /// Inline right-hand detail panel that replaces detail modals.
  final double detailDrawerWidth;

  /// Section navigation inside a work area (settings).
  final double sectionNavWidth;

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
  final Duration motionNormal;

  const ShellVibeTokens({
    required this.canvas,
    required this.canvasGlow,
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
    this.brandBright = const Color(0xFFA8AEFF),
    this.brandSoft = const Color(0xFFC6CAFF),
    required this.brandInk,
    required this.brandGradientTop,
    required this.brandGradientBottom,
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
    this.radiusMedium = 9,
    this.radiusLarge = 12,
    this.radiusOverlay = 14,
    this.radiusPill = 999,
    this.pagePadding = 16,
    this.controlHeight = 34,
    this.panelGap = 10,
    this.rowHeight = 48,
    this.railWidth = 56,
    this.contextColumnWidth = 240,
    this.detailDrawerWidth = 284,
    this.sectionNavWidth = 190,
    this.touchTarget = 44,
    this.breakpointCompact = 640,
    this.breakpointMedium = 900,
    this.breakpointExpanded = 1180,
    this.breakpointRail = 720,
    this.breakpointRailTouch = 800,
    this.motionFast = const Duration(milliseconds: 120),
    this.motionNormal = const Duration(milliseconds: 180),
  });

  static const dark = ShellVibeTokens(
    canvas: Color(0xFF0A0B11),
    canvasGlow: Color(0xFF171B2B),
    surface: Color(0xFF141726),
    surfaceLow: Color(0xFF0F111C),
    surfaceRaised: Color(0xFF1B1F30),
    terminalBg: Color(0xFF101218),
    terminalChrome: Color(0xFF151827),
    railBg: Color(0xFF171A26),
    // rgba(255,255,255,0.055) — the one hairline Nocturne uses everywhere.
    border: Color(0x0EFFFFFF),
    textPrimary: Color(0xFFEDEFF7),
    textSecondary: Color(0xFFD9DDEA),
    textMuted: Color(0xFF8E96AC),
    textSubtle: Color(0xFF5F667E),
    brand: Color(0xFF8B93FF),
    brandInk: Color(0xFF0B0D16),
    brandGradientTop: Color(0xFF9AA1FF),
    brandGradientBottom: Color(0xFF6F77EA),
    info: Color(0xFF8AB4F8),
    success: Color(0xFF7FD1A6),
    warning: Color(0xFFE3C179),
    danger: Color(0xFFF08C9E),
    shadowColor: Color(0x80000000),
    shadowColorStrong: Color(0xA6000000),
  );

  /// Daylight counterpart. Nocturne is authored dark; the light theme mirrors
  /// its structure (same roles, same radii) with inverted surfaces so the
  /// gradients and hairlines still read.
  static const light = ShellVibeTokens(
    canvas: Color(0xFFF2F4F8),
    canvasGlow: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceLow: Color(0xFFF7F8FB),
    surfaceRaised: Color(0xFFFFFFFF),
    terminalBg: Color(0xFF101218),
    terminalChrome: Color(0xFF151827),
    railBg: Color(0xFFFFFFFF),
    border: Color(0x14101218),
    textPrimary: Color(0xFF171B21),
    textSecondary: Color(0xFF333A47),
    textMuted: Color(0xFF667085),
    textSubtle: Color(0xFF8A93A6),
    brand: Color(0xFF5058D8),
    brandBright: Color(0xFF3D44B8),
    brandSoft: Color(0xFF636AE8),
    brandInk: Color(0xFFFFFFFF),
    brandGradientTop: Color(0xFF6F77EA),
    brandGradientBottom: Color(0xFF4C55CE),
    info: Color(0xFF2563EB),
    success: Color(0xFF15803D),
    warning: Color(0xFFB45309),
    danger: Color(0xFFBE123C),
    dangerMutedSurface: Color(0xFFFFEBEF),
    dangerMutedText: Color(0xFF9F1239),
    dangerMutedBorder: Color(0xFFFCA5A5),
    shadowColor: Color(0x14101218),
    shadowColorStrong: Color(0x24101218),
  );

  static ShellVibeTokens resolve(BuildContext context) {
    return Theme.of(context).extension<ShellVibeTokens>() ??
        (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

  /// The night ground: a soft glow thrown from above the top-left corner.
  Gradient get canvasGradient => RadialGradient(
    center: const Alignment(-0.64, -1.24),
    radius: 1.1,
    colors: [canvasGlow, canvas],
    stops: const [0, 0.62],
  );

  /// A floating panel's fill.
  ///
  /// The design anchors the gradient's end to a pixel distance from the panel
  /// top (140–300px depending on the panel), not to its height, so tall and
  /// short panels share the same top-lit falloff. [gradientExtent] is that
  /// distance and [height] the panel's laid-out height; pass the latter from a
  /// `LayoutBuilder` to keep the stop honest.
  Gradient panelGradient({double gradientExtent = 200, double? height}) {
    final stop = height == null || height <= 0
        ? 1.0
        : (gradientExtent / height).clamp(0.05, 1.0);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [surface, surfaceLow],
      stops: [0, stop.toDouble()],
    );
  }

  /// The raised fill of a primary action.
  Gradient get brandGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [brandGradientTop, brandGradientBottom],
  );

  /// `inset 0 1px 0 rgba(255,255,255,.07), 0 10px 30px rgba(0,0,0,.5)`.
  ///
  /// Flutter has no inset shadow, so the top-light half is drawn as a hairline
  /// border by the panel widgets; this carries the drop half.
  List<BoxShadow> get shadowPanel => [
    BoxShadow(color: shadowColor, blurRadius: 30, offset: const Offset(0, 10)),
  ];

  /// `0 30px 80px rgba(0,0,0,.65)` — palette, dialogs.
  List<BoxShadow> get shadowOverlay => [
    BoxShadow(
      color: shadowColorStrong,
      blurRadius: 80,
      offset: const Offset(0, 30),
    ),
  ];

  /// `0 6px 18px rgba(139,147,255,.3)` — under primary actions.
  List<BoxShadow> get shadowBrand => [
    BoxShadow(
      color: brand.withValues(alpha: 0.3),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];

  /// Halo around a live indicator.
  List<BoxShadow> glow(Color color, {double alpha = 0.9, double blur = 10}) => [
    BoxShadow(
      color: color.withValues(alpha: alpha),
      blurRadius: blur,
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
    Color? canvasGlow,
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
    Color? brandGradientTop,
    Color? brandGradientBottom,
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
    double? sectionNavWidth,
    double? touchTarget,
    double? breakpointCompact,
    double? breakpointMedium,
    double? breakpointExpanded,
    double? breakpointRail,
    double? breakpointRailTouch,
    Duration? motionFast,
    Duration? motionNormal,
  }) {
    return ShellVibeTokens(
      canvas: canvas ?? this.canvas,
      canvasGlow: canvasGlow ?? this.canvasGlow,
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
      brandGradientTop: brandGradientTop ?? this.brandGradientTop,
      brandGradientBottom: brandGradientBottom ?? this.brandGradientBottom,
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
      sectionNavWidth: sectionNavWidth ?? this.sectionNavWidth,
      touchTarget: touchTarget ?? this.touchTarget,
      breakpointCompact: breakpointCompact ?? this.breakpointCompact,
      breakpointMedium: breakpointMedium ?? this.breakpointMedium,
      breakpointExpanded: breakpointExpanded ?? this.breakpointExpanded,
      breakpointRail: breakpointRail ?? this.breakpointRail,
      breakpointRailTouch: breakpointRailTouch ?? this.breakpointRailTouch,
      motionFast: motionFast ?? this.motionFast,
      motionNormal: motionNormal ?? this.motionNormal,
    );
  }

  @override
  ShellVibeTokens lerp(covariant ShellVibeTokens? other, double t) {
    if (other == null) return this;
    return ShellVibeTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      canvasGlow: Color.lerp(canvasGlow, other.canvasGlow, t)!,
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
      brandGradientTop: Color.lerp(
        brandGradientTop,
        other.brandGradientTop,
        t,
      )!,
      brandGradientBottom: Color.lerp(
        brandGradientBottom,
        other.brandGradientBottom,
        t,
      )!,
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
      sectionNavWidth: _lerpDouble(sectionNavWidth, other.sectionNavWidth, t),
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
      motionNormal: t < 0.5 ? motionNormal : other.motionNormal,
    );
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// Backwards compatibility alias
