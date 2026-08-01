import 'package:flutter/material.dart';

/// Terly's shared visual contract.
///
/// Terminal ANSI palettes intentionally live outside this extension. The app
/// chrome keeps a stable identity while terminal sessions remain customizable.
@immutable
class TerlyTokens extends ThemeExtension<TerlyTokens> {
  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color brand;
  final Color info;
  final Color success;
  final Color warning;
  final Color danger;

  final double radiusSmall;
  final double radiusMedium;
  final double radiusLarge;
  final double pagePadding;
  final double controlHeight;
  final Duration motionFast;
  final Duration motionNormal;

  const TerlyTokens({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.brand,
    required this.info,
    required this.success,
    required this.warning,
    required this.danger,
    this.radiusSmall = 4,
    this.radiusMedium = 6,
    this.radiusLarge = 8,
    this.pagePadding = 20,
    this.controlHeight = 40,
    this.motionFast = const Duration(milliseconds: 120),
    this.motionNormal = const Duration(milliseconds: 180),
  });

  static const dark = TerlyTokens(
    canvas: Color(0xFF0B0E12),
    surface: Color(0xFF11161C),
    surfaceRaised: Color(0xFF171D25),
    border: Color(0xFF27303A),
    textPrimary: Color(0xFFF4F7FA),
    textMuted: Color(0xFF94A0AE),
    brand: Color(0xFF5EEAD4),
    info: Color(0xFF60A5FA),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFFB7185),
  );

  static const light = TerlyTokens(
    canvas: Color(0xFFF5F7F9),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEEF1F4),
    border: Color(0xFFD8DEE5),
    textPrimary: Color(0xFF171B21),
    textMuted: Color(0xFF667085),
    brand: Color(0xFF0F766E),
    info: Color(0xFF2563EB),
    success: Color(0xFF15803D),
    warning: Color(0xFFB45309),
    danger: Color(0xFFBE123C),
  );

  static TerlyTokens resolve(BuildContext context) {
    return Theme.of(context).extension<TerlyTokens>() ??
        (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

  @override
  TerlyTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? textPrimary,
    Color? textMuted,
    Color? brand,
    Color? info,
    Color? success,
    Color? warning,
    Color? danger,
    double? radiusSmall,
    double? radiusMedium,
    double? radiusLarge,
    double? pagePadding,
    double? controlHeight,
    Duration? motionFast,
    Duration? motionNormal,
  }) {
    return TerlyTokens(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      brand: brand ?? this.brand,
      info: info ?? this.info,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      radiusSmall: radiusSmall ?? this.radiusSmall,
      radiusMedium: radiusMedium ?? this.radiusMedium,
      radiusLarge: radiusLarge ?? this.radiusLarge,
      pagePadding: pagePadding ?? this.pagePadding,
      controlHeight: controlHeight ?? this.controlHeight,
      motionFast: motionFast ?? this.motionFast,
      motionNormal: motionNormal ?? this.motionNormal,
    );
  }

  @override
  TerlyTokens lerp(covariant TerlyTokens? other, double t) {
    if (other == null) return this;
    return TerlyTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      info: Color.lerp(info, other.info, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      radiusSmall: _lerpDouble(radiusSmall, other.radiusSmall, t),
      radiusMedium: _lerpDouble(radiusMedium, other.radiusMedium, t),
      radiusLarge: _lerpDouble(radiusLarge, other.radiusLarge, t),
      pagePadding: _lerpDouble(pagePadding, other.pagePadding, t),
      controlHeight: _lerpDouble(controlHeight, other.controlHeight, t),
      motionFast: t < 0.5 ? motionFast : other.motionFast,
      motionNormal: t < 0.5 ? motionNormal : other.motionNormal,
    );
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
