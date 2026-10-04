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

/// The terminal font size range: the Settings slider's ends, and where the
/// zoom shortcuts stop.
const double kTerminalFontSizeMin = 10;
const double kTerminalFontSizeMax = 24;

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

  /// Desktop only. An OS notification when something the user would otherwise
  /// miss happens while the window is hidden, minimised or unfocused (or in a
  /// tab they are not looking at): a session drops, a forward stops with an
  /// error, a terminal rings the bell or asks for attention (OSC 9 / 777).
  /// While the vault is locked the text is generic, so nothing that names a
  /// host reaches the notification centre.
  final bool desktopNotifications;

  const AppSettingsModel({
    this.themeMode = ThemeMode.system,
    this.palette = AppPalette.oled,
    this.terminalPalette = TerminalPalette.matchApp,
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
    this.desktopNotifications = true,
  });

  /// The brightness the app is drawn in, for callers with no theme to read it
  /// from. Widgets should prefer `Theme.of(context).brightness`.
  Brightness get effectiveBrightness => switch (themeMode) {
    ThemeMode.dark => Brightness.dark,
    ThemeMode.light => Brightness.light,
    ThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
  };

  /// The scheme the terminal paints with while the app is drawn in
  /// [brightness]. [TerminalPalette.matchApp] takes the scheme paired with
  /// [palette], so the terminal does not sit as a black slab inside a light
  /// theme; any explicit choice is returned as it is.
  TerminalPalette resolvedTerminalPalette(Brightness brightness) {
    if (terminalPalette != TerminalPalette.matchApp) return terminalPalette;
    final (dark, light) = switch (palette) {
      AppPalette.dark => (
        TerminalPalette.nocturne,
        TerminalPalette.githubLight,
      ),
      AppPalette.oled => (TerminalPalette.oled, TerminalPalette.githubLight),
      AppPalette.teal => (TerminalPalette.dark, TerminalPalette.githubLight),
      AppPalette.catppuccin => (
        TerminalPalette.catppuccinMocha,
        TerminalPalette.catppuccinLatte,
      ),
      AppPalette.nord => (TerminalPalette.nord, TerminalPalette.nordLight),
      AppPalette.dracula => (
        TerminalPalette.dracula,
        TerminalPalette.githubLight,
      ),
      AppPalette.solarizedDark => (
        TerminalPalette.solarizedDark,
        TerminalPalette.solarizedLight,
      ),
      AppPalette.tokyoNight => (
        TerminalPalette.tokyoNight,
        TerminalPalette.tokyoNightDay,
      ),
      AppPalette.gruvbox => (
        TerminalPalette.gruvboxDark,
        TerminalPalette.gruvboxLight,
      ),
      AppPalette.oneDark => (TerminalPalette.oneDark, TerminalPalette.oneLight),
    };
    return brightness == Brightness.dark ? dark : light;
  }

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
    bool? desktopNotifications,
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
      desktopNotifications: desktopNotifications ?? this.desktopNotifications,
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
    'desktopNotifications': desktopNotifications,
  };

  factory AppSettingsModel.fromJson(Map<String, dynamic> json) {
    return AppSettingsModel(
      themeMode: ThemeMode.values.firstWhere(
        (e) => e.name == json['themeMode'],
        orElse: () => ThemeMode.system,
      ),
      // An unreadable or absent palette name lands on the same default a
      // fresh install gets, so the two paths cannot disagree.
      palette: AppPalette.values.firstWhere(
        (e) => e.name == json['palette'],
        orElse: () => AppPalette.oled,
      ),
      terminalPalette: TerminalPalette.values.firstWhere(
        (e) => e.name == json['terminalPalette'],
        orElse: () => TerminalPalette.matchApp,
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
      desktopNotifications: (json['desktopNotifications'] as bool?) ?? true,
    );
  }
}
