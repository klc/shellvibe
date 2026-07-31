import 'package:flutter/material.dart';

enum AppPalette { dark, oled, catppuccin, nord }

enum AppCursorStyle { block, underline, bar }

/// Model representing global application settings.
class AppSettingsModel {
  final ThemeMode themeMode;
  final AppPalette palette;
  final String fontFamily;
  final double fontSize;
  final AppCursorStyle cursorStyle;
  final int autoLockTimerSeconds;
  final int clipboardAutoClearSeconds;

  const AppSettingsModel({
    this.themeMode = ThemeMode.dark,
    this.palette = AppPalette.dark,
    this.fontFamily = 'RobotoMono',
    this.fontSize = 14.0,
    this.cursorStyle = AppCursorStyle.block,
    this.autoLockTimerSeconds = 0,
    this.clipboardAutoClearSeconds = 30,
  });

  AppSettingsModel copyWith({
    ThemeMode? themeMode,
    AppPalette? palette,
    String? fontFamily,
    double? fontSize,
    AppCursorStyle? cursorStyle,
    int? autoLockTimerSeconds,
    int? clipboardAutoClearSeconds,
  }) {
    return AppSettingsModel(
      themeMode: themeMode ?? this.themeMode,
      palette: palette ?? this.palette,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      cursorStyle: cursorStyle ?? this.cursorStyle,
      autoLockTimerSeconds: autoLockTimerSeconds ?? this.autoLockTimerSeconds,
      clipboardAutoClearSeconds:
          clipboardAutoClearSeconds ?? this.clipboardAutoClearSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'palette': palette.name,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'cursorStyle': cursorStyle.name,
        'autoLockTimerSeconds': autoLockTimerSeconds,
        'clipboardAutoClearSeconds': clipboardAutoClearSeconds,
      };

  factory AppSettingsModel.fromJson(Map<String, dynamic> json) {
    return AppSettingsModel(
      themeMode: ThemeMode.values.firstWhere(
        (e) => e.name == json['themeMode'],
        orElse: () => ThemeMode.dark,
      ),
      palette: AppPalette.values.firstWhere(
        (e) => e.name == json['palette'],
        orElse: () => AppPalette.dark,
      ),
      fontFamily: (json['fontFamily'] as String?) ?? 'RobotoMono',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
      cursorStyle: AppCursorStyle.values.firstWhere(
        (e) => e.name == json['cursorStyle'],
        orElse: () => AppCursorStyle.block,
      ),
      autoLockTimerSeconds: (json['autoLockTimerSeconds'] as int?) ?? 0,
      clipboardAutoClearSeconds: (json['clipboardAutoClearSeconds'] as int?) ?? 30,
    );
  }
}
