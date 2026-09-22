import 'package:flutter/material.dart';

import '../../../../core/models/mosh_prediction_mode.dart';
import '../../../terminal/domain/models/terminal_palette.dart';

enum AppPalette {
  dark,
  oled,
  teal,
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

  /// Interface font id, resolved through `kUiFonts`. Separate from
  /// [fontFamily], which is the terminal's own face.
  final String uiFontFamily;
  final double fontSize;
  final double lineHeightFactor;
  final AppCursorStyle cursorStyle;
  final bool enableLigatures;
  final bool drawBoldTextWithBrightColors;
  final MoshPredictionMode moshPrediction;
  final int autoLockTimerSeconds;
  final int clipboardAutoClearSeconds;
  final String activeWorkspaceId;

  /// Desktop only. Closing the window hides it to the system tray (the menu
  /// bar on macOS) instead of quitting, so tunnels and sessions keep running;
  /// Quit is on the tray menu. Off, the tray icon is gone and closing the last
  /// window quits on Windows and Linux, as it did before.
  final bool keepRunningInTray;

  const AppSettingsModel({
    this.themeMode = ThemeMode.dark,
    this.palette = AppPalette.oled,
    this.terminalPalette = TerminalPalette.oled,
    this.fontFamily = 'RobotoMono',
    this.uiFontFamily = 'InterTight',
    this.fontSize = 14.0,
    this.lineHeightFactor = 1.4,
    this.cursorStyle = AppCursorStyle.block,
    this.enableLigatures = true,
    this.drawBoldTextWithBrightColors = true,
    this.moshPrediction = MoshPredictionMode.adaptive,
    this.autoLockTimerSeconds = 0,
    this.clipboardAutoClearSeconds = 30,
    this.activeWorkspaceId = 'default',
    this.keepRunningInTray = true,
  });

  AppSettingsModel copyWith({
    ThemeMode? themeMode,
    AppPalette? palette,
    TerminalPalette? terminalPalette,
    String? fontFamily,
    String? uiFontFamily,
    double? fontSize,
    double? lineHeightFactor,
    AppCursorStyle? cursorStyle,
    bool? enableLigatures,
    bool? drawBoldTextWithBrightColors,
    MoshPredictionMode? moshPrediction,
    int? autoLockTimerSeconds,
    int? clipboardAutoClearSeconds,
    String? activeWorkspaceId,
    bool? keepRunningInTray,
  }) {
    return AppSettingsModel(
      themeMode: themeMode ?? this.themeMode,
      palette: palette ?? this.palette,
      terminalPalette: terminalPalette ?? this.terminalPalette,
      fontFamily: fontFamily ?? this.fontFamily,
      uiFontFamily: uiFontFamily ?? this.uiFontFamily,
      fontSize: fontSize ?? this.fontSize,
      lineHeightFactor: lineHeightFactor ?? this.lineHeightFactor,
      cursorStyle: cursorStyle ?? this.cursorStyle,
      enableLigatures: enableLigatures ?? this.enableLigatures,
      drawBoldTextWithBrightColors:
          drawBoldTextWithBrightColors ?? this.drawBoldTextWithBrightColors,
      moshPrediction: moshPrediction ?? this.moshPrediction,
      autoLockTimerSeconds: autoLockTimerSeconds ?? this.autoLockTimerSeconds,
      clipboardAutoClearSeconds:
          clipboardAutoClearSeconds ?? this.clipboardAutoClearSeconds,
      activeWorkspaceId: activeWorkspaceId ?? this.activeWorkspaceId,
      keepRunningInTray: keepRunningInTray ?? this.keepRunningInTray,
    );
  }

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'palette': palette.name,
    'terminalPalette': terminalPalette.name,
    'fontFamily': fontFamily,
    'uiFontFamily': uiFontFamily,
    'fontSize': fontSize,
    'lineHeightFactor': lineHeightFactor,
    'cursorStyle': cursorStyle.name,
    'enableLigatures': enableLigatures,
    'drawBoldTextWithBrightColors': drawBoldTextWithBrightColors,
    'moshPrediction': moshPrediction.name,
    'autoLockTimerSeconds': autoLockTimerSeconds,
    'clipboardAutoClearSeconds': clipboardAutoClearSeconds,
    'activeWorkspaceId': activeWorkspaceId,
    'keepRunningInTray': keepRunningInTray,
  };

  factory AppSettingsModel.fromJson(Map<String, dynamic> json) {
    return AppSettingsModel(
      themeMode: ThemeMode.values.firstWhere(
        (e) => e.name == json['themeMode'],
        orElse: () => ThemeMode.dark,
      ),
      // An unreadable or absent palette name lands on the same default a
      // fresh install gets, so the two paths cannot disagree.
      palette: AppPalette.values.firstWhere(
        (e) => e.name == json['palette'],
        orElse: () => AppPalette.oled,
      ),
      terminalPalette: TerminalPalette.values.firstWhere(
        (e) => e.name == json['terminalPalette'],
        orElse: () => TerminalPalette.oled,
      ),
      fontFamily: (json['fontFamily'] as String?) ?? 'RobotoMono',
      uiFontFamily: (json['uiFontFamily'] as String?) ?? 'InterTight',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
      lineHeightFactor: (json['lineHeightFactor'] as num?)?.toDouble() ?? 1.4,
      cursorStyle: AppCursorStyle.values.firstWhere(
        (e) => e.name == json['cursorStyle'],
        orElse: () => AppCursorStyle.block,
      ),
      enableLigatures: (json['enableLigatures'] as bool?) ?? true,
      drawBoldTextWithBrightColors:
          (json['drawBoldTextWithBrightColors'] as bool?) ?? true,
      moshPrediction: MoshPredictionMode.values.firstWhere(
        (e) => e.name == json['moshPrediction'],
        orElse: () => MoshPredictionMode.adaptive,
      ),
      autoLockTimerSeconds: (json['autoLockTimerSeconds'] as int?) ?? 0,
      clipboardAutoClearSeconds:
          (json['clipboardAutoClearSeconds'] as int?) ?? 30,
      activeWorkspaceId: (json['activeWorkspaceId'] as String?) ?? 'default',
      keepRunningInTray: (json['keepRunningInTray'] as bool?) ?? true,
    );
  }
}
