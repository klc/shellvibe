import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../features/settings/domain/models/app_settings_model.dart';

class AppTheme {
  static ThemeData get darkTheme => buildTheme(const AppSettingsModel());

  static ShadThemeData get darkShadTheme => buildShadTheme(const AppSettingsModel());
  static ShadThemeData get lightShadTheme => buildShadTheme(const AppSettingsModel(themeMode: ThemeMode.light));

  static ShadThemeData buildShadTheme(AppSettingsModel settings) {
    final isDark = settings.themeMode != ThemeMode.light;

    ShadColorScheme colorScheme;
    switch (settings.palette) {
      case AppPalette.oled:
        colorScheme = const ShadSlateColorScheme.dark(
          background: Color(0xFF000000),
          card: Color(0xFF121212),
          primary: Color(0xFF00E676),
        );
        break;
      case AppPalette.catppuccin:
        colorScheme = const ShadSlateColorScheme.dark(
          background: Color(0xFF1E1E2E),
          card: Color(0xFF181825),
          primary: Color(0xFF8AADF4),
        );
        break;
      case AppPalette.nord:
        colorScheme = const ShadSlateColorScheme.dark(
          background: Color(0xFF2E3440),
          card: Color(0xFF3B4252),
          primary: Color(0xFF88C0D0),
        );
        break;
      case AppPalette.dark:
        colorScheme = isDark
            ? const ShadSlateColorScheme.dark(
                background: Color(0xFF0F172A),
                card: Color(0xFF1E293B),
                primary: Color(0xFF38BDF8),
              )
            : const ShadSlateColorScheme.light();
        break;
    }

    return ShadThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
    );
  }

  static ThemeData buildTheme(AppSettingsModel settings) {
    Color scaffoldBg;
    Color cardBg;
    Color primaryColor;
    Color accentColor;

    switch (settings.palette) {
      case AppPalette.oled:
        scaffoldBg = Colors.black;
        cardBg = const Color(0xFF121212);
        primaryColor = const Color(0xFF00E676);
        accentColor = const Color(0xFF18FFFF);
        break;
      case AppPalette.catppuccin:
        scaffoldBg = const Color(0xFF1E1E2E);
        cardBg = const Color(0xFF181825);
        primaryColor = const Color(0xFF89B4FA);
        accentColor = const Color(0xFFCBA6F7);
        break;
      case AppPalette.nord:
        scaffoldBg = const Color(0xFF2E3440);
        cardBg = const Color(0xFF3B4252);
        primaryColor = const Color(0xFF88C0D0);
        accentColor = const Color(0xFF81A1C1);
        break;
      case AppPalette.dark:
        scaffoldBg = const Color(0xFF18181B);
        cardBg = const Color(0xFF27272A);
        primaryColor = const Color(0xFF6366F1);
        accentColor = const Color(0xFFA855F7);
        break;
    }

    final isDark = settings.themeMode != ThemeMode.light;

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: isDark ? scaffoldBg : Colors.grey[50],
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: isDark ? Brightness.dark : Brightness.light,
        surface: isDark ? scaffoldBg : Colors.white,
        secondary: accentColor,
      ),
      cardTheme: CardThemeData(
        color: isDark ? cardBg : Colors.white,
        elevation: 1,
      ),
      fontFamily: settings.fontFamily,
      textTheme: TextTheme(
        bodyMedium: TextStyle(fontSize: settings.fontSize),
      ),
    );
  }
}

