import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../features/settings/domain/models/app_settings_model.dart';
import 'terly_tokens.dart';

class AppTheme {
  static ThemeData get darkTheme => buildTheme(const AppSettingsModel());

  static ShadThemeData get darkShadTheme =>
      buildShadTheme(const AppSettingsModel());
  static ShadThemeData get lightShadTheme =>
      buildShadTheme(const AppSettingsModel(themeMode: ThemeMode.light));

  static ShadThemeData buildShadTheme(AppSettingsModel settings) {
    final isDark = settings.themeMode == ThemeMode.system
        ? WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark
        : settings.themeMode == ThemeMode.dark;

    final tokens = isDark ? TerlyTokens.dark : TerlyTokens.light;

    ShadColorScheme colorScheme;
    if (!isDark) {
      colorScheme = const ShadSlateColorScheme.light(
        background: Color(0xFFF5F7F9),
        foreground: Color(0xFF171B21),
        card: Color(0xFFFFFFFF),
        cardForeground: Color(0xFF171B21),
        primary: Color(0xFF0F766E),
        primaryForeground: Color(0xFFFFFFFF),
        muted: Color(0xFFEEF1F4),
        mutedForeground: Color(0xFF667085),
        border: Color(0xFFD8DEE5),
        destructive: Color(0xFFBE123C),
      );
    } else {
      switch (settings.palette) {
        case AppPalette.oled:
          colorScheme = const ShadSlateColorScheme.dark(
            background: Color(0xFF000000),
            foreground: Color(0xFFF4F7FA),
            card: Color(0xFF080A0D),
            cardForeground: Color(0xFFF4F7FA),
            primary: Color(0xFF5EEAD4),
            primaryForeground: Color(0xFF06211E),
            muted: Color(0xFF11161C),
            mutedForeground: Color(0xFF94A0AE),
            border: Color(0xFF1F1F1F),
            destructive: Color(0xFFFB7185),
          );
          break;
        case AppPalette.catppuccin:
          colorScheme = const ShadSlateColorScheme.dark(
            background: Color(0xFF1E1E2E),
            card: Color(0xFF181825),
            primary: Color(0xFF5EEAD4),
            border: Color(0xFF313244),
          );
          break;
        case AppPalette.nord:
          colorScheme = const ShadSlateColorScheme.dark(
            background: Color(0xFF2E3440),
            card: Color(0xFF3B4252),
            primary: Color(0xFF5EEAD4),
            border: Color(0xFF4C566A),
          );
          break;
        case AppPalette.dracula:
          colorScheme = const ShadSlateColorScheme.dark(
            background: Color(0xFF282A36),
            card: Color(0xFF343746),
            primary: Color(0xFFBD93F9),
            border: Color(0xFF44475A),
          );
          break;
        case AppPalette.solarizedDark:
          colorScheme = const ShadSlateColorScheme.dark(
            background: Color(0xFF002B36),
            card: Color(0xFF073642),
            primary: Color(0xFF2AA198),
            border: Color(0xFF586E75),
          );
          break;
        case AppPalette.tokyoNight:
          colorScheme = const ShadSlateColorScheme.dark(
            background: Color(0xFF1A1B26),
            card: Color(0xFF24283B),
            primary: Color(0xFF7AA2F7),
            border: Color(0xFF414868),
          );
          break;
        case AppPalette.gruvbox:
          colorScheme = const ShadSlateColorScheme.dark(
            background: Color(0xFF282828),
            card: Color(0xFF3C3836),
            primary: Color(0xFFFE8019),
            border: Color(0xFF504945),
          );
          break;
        case AppPalette.oneDark:
          colorScheme = const ShadSlateColorScheme.dark(
            background: Color(0xFF21252B),
            card: Color(0xFF282C34),
            primary: Color(0xFF61AFEF),
            border: Color(0xFF3E4451),
          );
          break;
        case AppPalette.dark:
          colorScheme = const ShadSlateColorScheme.dark(
            background: Color(0xFF0B0E12),
            foreground: Color(0xFFF4F7FA),
            card: Color(0xFF11161C),
            cardForeground: Color(0xFFF4F7FA),
            primary: Color(0xFF5EEAD4),
            primaryForeground: Color(0xFF06211E),
            muted: Color(0xFF171D25),
            mutedForeground: Color(0xFF94A0AE),
            border: Color(0xFF27303A),
            destructive: Color(0xFFFB7185),
          );
          break;
      }
    }

    return ShadThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      radius: BorderRadius.circular(tokens.radiusMedium),
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

  static ThemeData buildTheme(AppSettingsModel settings) {
    final isDark = settings.themeMode == ThemeMode.system
        ? WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark
        : settings.themeMode == ThemeMode.dark;

    Color scaffoldBg;
    Color cardBg;
    Color primaryColor;
    Color accentColor;
    TerlyTokens tokens;

    if (!isDark) {
      tokens = TerlyTokens.light;
      scaffoldBg = tokens.canvas;
      cardBg = tokens.surface;
      primaryColor = tokens.brand;
      accentColor = tokens.info;
    } else {
      switch (settings.palette) {
        case AppPalette.oled:
          scaffoldBg = Colors.black;
          cardBg = Colors.black;
          primaryColor = const Color(0xFF00E676);
          accentColor = const Color(0xFF18FFFF);
          tokens = TerlyTokens.dark.copyWith(
            canvas: Colors.black,
            surface: const Color(0xFF080A0D),
            surfaceRaised: const Color(0xFF11161C),
          );
          break;
        case AppPalette.catppuccin:
          scaffoldBg = const Color(0xFF1E1E2E);
          cardBg = const Color(0xFF181825);
          primaryColor = const Color(0xFF89B4FA);
          accentColor = const Color(0xFFCBA6F7);
          tokens = TerlyTokens.dark.copyWith(
            canvas: scaffoldBg,
            surface: cardBg,
            surfaceRaised: const Color(0xFF24273A),
          );
          break;
        case AppPalette.nord:
          scaffoldBg = const Color(0xFF2E3440);
          cardBg = const Color(0xFF3B4252);
          primaryColor = const Color(0xFF88C0D0);
          accentColor = const Color(0xFF81A1C1);
          tokens = TerlyTokens.dark.copyWith(
            canvas: scaffoldBg,
            surface: cardBg,
            surfaceRaised: const Color(0xFF434C5E),
          );
          break;
        case AppPalette.dracula:
          scaffoldBg = const Color(0xFF282A36);
          cardBg = const Color(0xFF343746);
          primaryColor = const Color(0xFFBD93F9);
          accentColor = const Color(0xFFFF79C6);
          tokens = TerlyTokens.dark.copyWith(
            canvas: scaffoldBg,
            surface: cardBg,
            surfaceRaised: const Color(0xFF44475A),
          );
          break;
        case AppPalette.solarizedDark:
          scaffoldBg = const Color(0xFF002B36);
          cardBg = const Color(0xFF073642);
          primaryColor = const Color(0xFF2AA198);
          accentColor = const Color(0xFF268BD2);
          tokens = TerlyTokens.dark.copyWith(
            canvas: scaffoldBg,
            surface: cardBg,
            surfaceRaised: const Color(0xFF586E75),
          );
          break;
        case AppPalette.tokyoNight:
          scaffoldBg = const Color(0xFF1A1B26);
          cardBg = const Color(0xFF24283B);
          primaryColor = const Color(0xFF7AA2F7);
          accentColor = const Color(0xFFBB9AF7);
          tokens = TerlyTokens.dark.copyWith(
            canvas: scaffoldBg,
            surface: cardBg,
            surfaceRaised: const Color(0xFF414868),
          );
          break;
        case AppPalette.gruvbox:
          scaffoldBg = const Color(0xFF282828);
          cardBg = const Color(0xFF3C3836);
          primaryColor = const Color(0xFFFE8019);
          accentColor = const Color(0xFFFABD2F);
          tokens = TerlyTokens.dark.copyWith(
            canvas: scaffoldBg,
            surface: cardBg,
            surfaceRaised: const Color(0xFF504945),
          );
          break;
        case AppPalette.oneDark:
          scaffoldBg = const Color(0xFF21252B);
          cardBg = const Color(0xFF282C34);
          primaryColor = const Color(0xFF61AFEF);
          accentColor = const Color(0xFFC678DD);
          tokens = TerlyTokens.dark.copyWith(
            canvas: scaffoldBg,
            surface: cardBg,
            surfaceRaised: const Color(0xFF3E4451),
          );
          break;
        case AppPalette.dark:
          scaffoldBg = TerlyTokens.dark.canvas;
          cardBg = TerlyTokens.dark.surface;
          primaryColor = TerlyTokens.dark.brand;
          accentColor = TerlyTokens.dark.info;
          tokens = TerlyTokens.dark;
          break;
      }
    }

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: scaffoldBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: isDark ? Brightness.dark : Brightness.light,
        surface: scaffoldBg,
        secondary: accentColor,
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
      textTheme: TextTheme(
        headlineSmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: tokens.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: tokens.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: tokens.textPrimary,
        ),
        bodyLarge: TextStyle(fontSize: 14, color: tokens.textPrimary),
        bodyMedium: TextStyle(fontSize: 13, color: tokens.textPrimary),
        bodySmall: TextStyle(fontSize: 12, color: tokens.textMuted),
        labelLarge: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        labelMedium: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        labelSmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.canvas,
        foregroundColor: tokens.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: tokens.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        shape: Border(bottom: BorderSide(color: tokens.border)),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surface,
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
          borderSide: BorderSide(color: tokens.brand, width: 1.5),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
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
        backgroundColor: tokens.surface,
        indicatorColor: tokens.brand.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? tokens.brand
                : tokens.textMuted,
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          side: BorderSide(color: tokens.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          side: BorderSide(color: tokens.border),
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
