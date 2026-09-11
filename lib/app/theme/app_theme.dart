import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/utils/platform_capabilities.dart';
import '../../features/settings/domain/models/app_settings_model.dart';
import 'app_palette_definitions.dart';
import 'shellvibe_tokens.dart';
import 'ui_font.dart';

class AppTheme {
  static ThemeData get darkTheme => buildTheme(const AppSettingsModel());

  static ShadThemeData get darkShadTheme =>
      buildShadTheme(const AppSettingsModel());
  static ShadThemeData get lightShadTheme =>
      buildShadTheme(const AppSettingsModel(themeMode: ThemeMode.light));

  /// Whichever of the palette's darkest and lightest inks reads better on
  /// [fill]. Used where the token contract has no dedicated on-colour.
  static Color legibleInk(Color fill, ShellVibeTokens tokens) {
    final candidates = [tokens.brandInk, tokens.textPrimary, tokens.canvas];
    var best = candidates.first;
    var bestRatio = 0.0;
    for (final candidate in candidates) {
      final ratio = _contrastRatio(candidate, fill);
      if (ratio > bestRatio) {
        bestRatio = ratio;
        best = candidate;
      }
    }
    // Nothing in the palette clears AA on this fill, so fall back to the
    // absolutes rather than shipping an unreadable label.
    if (bestRatio < 4.5) {
      return _contrastRatio(const Color(0xFF000000), fill) >
              _contrastRatio(const Color(0xFFFFFFFF), fill)
          ? const Color(0xFF000000)
          : const Color(0xFFFFFFFF);
    }
    return best;
  }

  /// WCAG 2.1 contrast ratio, 1.0 (identical) to 21.0 (black on white).
  static double _contrastRatio(Color a, Color b) {
    double luminance(Color color) {
      double channel(double value) => value <= 0.03928
          ? value / 12.92
          : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * channel(color.r) +
          0.7152 * channel(color.g) +
          0.0722 * channel(color.b);
    }

    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  static bool _resolveIsDark(
    AppSettingsModel settings,
    Brightness? brightness,
  ) {
    if (brightness != null) return brightness == Brightness.dark;
    if (settings.themeMode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    return settings.themeMode == ThemeMode.dark;
  }

  static ShadThemeData buildShadTheme(
    AppSettingsModel settings, {
    Brightness? brightness,
  }) {
    final isDark = _resolveIsDark(settings, brightness);
    final def = AppPaletteDefinition.forPalette(settings.palette);
    final tokens = isDark ? def.darkTokens : def.lightTokens;
    final colorScheme = AppPaletteDefinition.buildShadColorScheme(
      settings.palette,
      isDark: isDark,
    );

    return ShadThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      radius: BorderRadius.circular(tokens.radiusMedium),
      // Shadcn builds its own text theme rather than reading Material's, so
      // the family has to be handed over here too or its inputs, selects and
      // popovers keep drawing in the platform font.
      textTheme: ShadTextTheme(
        family: resolveUiFontFamily(settings.uiFontFamily),
      ).apply(fontFamilyFallback: kUiFontFamilyFallback),
      inputTheme: ShadInputTheme(
        // Default input padding is EdgeInsets.symmetric(horizontal: 12,
        // vertical: 8) and its text uses theme.textTheme.muted (fontSize 14,
        // height 20/14 => exact 20px line height), giving a natural height
        // of 20 + 16 = 36px — the minHeight floor below is not enough on its
        // own to reach 34px since it's a floor, not a cap. Trimming vertical
        // padding to 7 (total 14) yields 20 + 14 = 34px, matching
        // tokens.controlHeight exactly, same derivation as selectTheme below.
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        constraints: BoxConstraints(minHeight: tokens.controlHeight),
      ),
      selectTheme: ShadSelectTheme(
        // Default select padding is EdgeInsets.symmetric(horizontal: 12,
        // vertical: 8) and the trigger text uses theme.textTheme.muted
        // (fontSize 14, height 20/14 => exact 20px line height), giving a
        // natural height of 20 + 16 = 36px. Trimming vertical padding to 7
        // (total 14) yields 20 + 14 = 34px, matching tokens.controlHeight
        // exactly.
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      ),
    );
  }

  static ThemeData buildTheme(
    AppSettingsModel settings, {
    Brightness? brightness,
  }) {
    final isDark = _resolveIsDark(settings, brightness);
    final def = AppPaletteDefinition.forPalette(settings.palette);
    final tokens = isDark ? def.darkTokens : def.lightTokens;
    final scaffoldBg = tokens.canvas;
    final cardBg = tokens.surface;
    final primaryColor = tokens.brand;
    final accentColor = isDark ? def.darkSecondary : def.lightSecondary;

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: scaffoldBg,
      // Applied to the Material typography before the ramp below is merged
      // over it, so every step inherits the family without repeating it.
      fontFamily: resolveUiFontFamily(settings.uiFontFamily),
      fontFamilyFallback: kUiFontFamilyFallback,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        brightness: isDark ? Brightness.dark : Brightness.light,
        surface: scaffoldBg,
        secondary: accentColor,
        // Pinning a colour without pinning its on-colour leaves Material
        // deriving the label from the seed's tonal ramp rather than from the
        // colour actually used, which is how a palette ends up with an
        // unreadable button. brandInk is the token contract's own answer for
        // "what is legible on brand"; secondary has no token, so it takes
        // whichever of ink or paper reads better on it.
        onPrimary: tokens.brandInk,
        onSecondary: legibleInk(accentColor, tokens),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          side: BorderSide(color: tokens.border),
        ),
      ),
      // Nocturne's ramp (5A). Sizes tighten their tracking as they grow, which
      // is what keeps the display and title steps from reading as web copy.
      textTheme: TextTheme(
        // Phone screen title.
        displaySmall: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.7,
          color: tokens.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
          color: tokens.textPrimary,
        ),
        // Work area title.
        titleLarge: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: tokens.textPrimary,
        ),
        // Panel head.
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: tokens.textPrimary,
        ),
        // List row name.
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: tokens.textSecondary,
        ),
        bodyLarge: TextStyle(fontSize: 14, color: tokens.textPrimary),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: tokens.textPrimary,
        ),
        bodySmall: TextStyle(fontSize: 12, color: tokens.textMuted),
        labelLarge: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        labelMedium: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        labelSmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        // Nocturne app bars sit on the canvas rather than on a bar of their
        // own, and the panel below them supplies the edge — so no fill and no
        // bottom rule here.
        backgroundColor: Colors.transparent,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: tokens.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // Fields are cut into the panel they sit on, not stacked on top of it,
        // so the fill is a translucent lift rather than another opaque surface.
        fillColor: tokens.textPrimary.withValues(alpha: 0.035),
        hintStyle: TextStyle(color: tokens.textMuted, fontSize: 13),
        prefixIconColor: tokens.textMuted,
        suffixIconColor: tokens.textMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          borderSide: BorderSide(
            color: tokens.brand.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          // 40px is a comfortable pointer target and an uncomfortable thumb
          // one, so touch platforms get the full touch target instead.
          minimumSize: WidgetStatePropertyAll(
            isMobilePlatform
                ? Size(tokens.touchTarget, tokens.touchTarget)
                : const Size(40, 40),
          ),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return tokens.textMuted.withValues(alpha: 0.5);
            }
            return tokens.textMuted;
          }),
          overlayColor: WidgetStatePropertyAll(
            tokens.brand.withValues(alpha: 0.08),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusMedium),
            ),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        minTileHeight: 52,
        iconColor: tokens.textMuted,
        textColor: tokens.textPrimary,
        subtitleTextStyle: TextStyle(fontSize: 12, color: tokens.textMuted),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        backgroundColor: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: tokens.brand.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? const Color(0xFFA8AEFF)
                : tokens.textMuted,
          ),
        ),
      ),
      // Overlays sit one step above a panel: raised fill, wider radius and a
      // brighter hairline so they read as detached from the slabs behind them.
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusOverlay),
          side: BorderSide(color: tokens.textPrimary.withValues(alpha: 0.09)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        barrierColor: const Color(0xA606070C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusOverlay),
          side: BorderSide(color: tokens.textPrimary.withValues(alpha: 0.09)),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
          border: Border.all(color: tokens.border),
        ),
        textStyle: TextStyle(color: tokens.textPrimary, fontSize: 12),
      ),
      extensions: [tokens],
    );
  }
}
