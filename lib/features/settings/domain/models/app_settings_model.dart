import 'package:flutter/material.dart';

import '../../../terminal/domain/models/terminal_palette.dart';

enum AppPalette {
  dark,
  oled,
  catppuccin,
  nord,
  dracula,
  solarizedDark,
  tokyoNight,
  gruvbox,
  oneDark,
}

enum AppCursorStyle { block, underline, bar }

/// Model representing global application settings.
class AppSettingsModel {
  final ThemeMode themeMode;
  final AppPalette palette;
  final TerminalPalette terminalPalette;
  final String fontFamily;
  final double fontSize;
  final AppCursorStyle cursorStyle;
  final bool enableLigatures;
  final int autoLockTimerSeconds;
  final int clipboardAutoClearSeconds;
  final String activeWorkspaceId;

  const AppSettingsModel({
    this.themeMode = ThemeMode.dark,
    this.palette = AppPalette.dark,
    this.terminalPalette = TerminalPalette.dark,
    this.fontFamily = 'RobotoMono',
    this.fontSize = 14.0,
    this.cursorStyle = AppCursorStyle.block,
    this.enableLigatures = true,
    this.autoLockTimerSeconds = 0,
    this.clipboardAutoClearSeconds = 30,
    this.activeWorkspaceId = 'default',
  });

  AppSettingsModel copyWith({
    ThemeMode? themeMode,
    AppPalette? palette,
    TerminalPalette? terminalPalette,
    String? fontFamily,
    double? fontSize,
    AppCursorStyle? cursorStyle,
    bool? enableLigatures,
    int? autoLockTimerSeconds,
    int? clipboardAutoClearSeconds,
    String? activeWorkspaceId,
  }) {
    return AppSettingsModel(
      themeMode: themeMode ?? this.themeMode,
      palette: palette ?? this.palette,
      terminalPalette: terminalPalette ?? this.terminalPalette,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      cursorStyle: cursorStyle ?? this.cursorStyle,
      enableLigatures: enableLigatures ?? this.enableLigatures,
      autoLockTimerSeconds: autoLockTimerSeconds ?? this.autoLockTimerSeconds,
      clipboardAutoClearSeconds:
          clipboardAutoClearSeconds ?? this.clipboardAutoClearSeconds,
      activeWorkspaceId: activeWorkspaceId ?? this.activeWorkspaceId,
    );
  }

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'palette': palette.name,
    'terminalPalette': terminalPalette.name,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'cursorStyle': cursorStyle.name,
    'enableLigatures': enableLigatures,
    'autoLockTimerSeconds': autoLockTimerSeconds,
    'clipboardAutoClearSeconds': clipboardAutoClearSeconds,
    'activeWorkspaceId': activeWorkspaceId,
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
      terminalPalette: TerminalPalette.values.firstWhere(
        (e) => e.name == json['terminalPalette'],
        orElse: () => TerminalPalette.dark,
      ),
      fontFamily: (json['fontFamily'] as String?) ?? 'RobotoMono',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
      cursorStyle: AppCursorStyle.values.firstWhere(
        (e) => e.name == json['cursorStyle'],
        orElse: () => AppCursorStyle.block,
      ),
      enableLigatures: (json['enableLigatures'] as bool?) ?? true,
      autoLockTimerSeconds: (json['autoLockTimerSeconds'] as int?) ?? 0,
      clipboardAutoClearSeconds:
          (json['clipboardAutoClearSeconds'] as int?) ?? 30,
      activeWorkspaceId: (json['activeWorkspaceId'] as String?) ?? 'default',
    );
  }
}
