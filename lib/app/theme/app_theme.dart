import 'package:flutter/material.dart';
import '../../features/settings/domain/models/app_settings_model.dart';

class AppTheme {
  static ThemeData get darkTheme => buildTheme(const AppSettingsModel());

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
