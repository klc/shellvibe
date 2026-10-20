import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/models/mosh_prediction_mode.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../terminal/domain/models/terminal_palette.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/app_settings_model.dart';
import '../../domain/services/biometric_lock_service.dart';
import '../../domain/services/clipboard_auto_clear_service.dart';

part 'settings_notifier.g.dart';

@riverpod
SettingsRepository settingsRepository(Ref ref) {
  final storage = ref.watch(secureStorageServiceProvider);
  return SettingsRepository(storage);
}

@riverpod
BiometricLockService biometricLockService(Ref ref) {
  return BiometricLockService();
}

@Riverpod(keepAlive: true)
ClipboardAutoClearService clipboardAutoClearService(Ref ref) {
  final service = ClipboardAutoClearService();
  // Never leave a pending timer that keeps clearing the clipboard after the
  // provider (and the widget that registered onCleared) is gone.
  ref.onDispose(service.cancelTimer);
  return service;
}

@riverpod
class SettingsNotifier extends _$SettingsNotifier {
  /// Most recently saved model, kept even while `state` is in `loading`.
  /// Setters derive from this so a second change made while the first save is
  /// in flight does not restart from the default model and wipe other fields.
  AppSettingsModel? _lastKnown;

  /// Serializes storage writes: a slow earlier save cannot land after a newer
  /// one and leave the UI disagreeing with storage.
  Future<void> _writeChain = Future.value();

  @override
  Future<AppSettingsModel> build() async {
    final repo = ref.watch(settingsRepositoryProvider);
    final loaded = await repo.loadSettings();
    // A save issued while the initial load was in flight must win over the
    // pre-save snapshot.
    _lastKnown ??= loaded;
    return _lastKnown!;
  }

  Future<void> updateSettings(AppSettingsModel updated) async {
    final previous = _base;
    _lastKnown = updated;
    state = AsyncValue.data(updated);
    final result = _writeChain.then((_) async {
      final repo = ref.read(settingsRepositoryProvider);
      await repo.saveSettings(updated);
      return updated;
    });
    _writeChain = result.then((_) {}, onError: (_) {});
    try {
      await result;
    } catch (e, st) {
      // The write failed: show what is actually stored, and let the caller
      // know.
      _lastKnown = previous;
      state = AsyncValue.data(previous);
      Error.throwWithStackTrace(e, st);
    }
  }

  AppSettingsModel get _base =>
      _lastKnown ?? state.value ?? const AppSettingsModel();

  /// Applies a settings blob that came out of a backup.
  ///
  /// [AppSettingsModel.fromJson] already falls back to a default for every
  /// field it cannot read, so a blob from another build or another platform is
  /// safe to parse. Two things still need handling here.
  ///
  /// `activeWorkspaceId` points at a database row. A backup taken on another
  /// device can name a workspace this one does not have, and the app would
  /// then believe it had a workspace open that does not exist.
  ///
  /// The auto-lock and clipboard timers are security settings. A loose value
  /// from an old backup can quietly relax a device that was tightened since.
  /// That is the user's call to make -- they asked for settings to be restored
  /// -- but it is not something to do without saying so, which is why the
  /// changes are returned rather than only applied.
  Future<List<String>> applyRestoredSettings(Map<String, dynamic> json) async {
    final current = _base;
    var restored = AppSettingsModel.fromJson(json);

    final db = ref.read(appDatabaseProvider);
    final workspace = await (db.select(
      db.workspaces,
    )..where((w) => w.id.equals(restored.activeWorkspaceId))).getSingleOrNull();

    if (workspace == null) {
      restored = restored.copyWith(activeWorkspaceId: 'default');
    }

    final notes = <String>[
      if (restored.autoLockTimerSeconds != current.autoLockTimerSeconds)
        'Auto-lock changed from ${_describeTimer(current.autoLockTimerSeconds)} '
            'to ${_describeTimer(restored.autoLockTimerSeconds)}.',
      if (restored.clipboardAutoClearSeconds !=
          current.clipboardAutoClearSeconds)
        'Clipboard auto-clear changed from '
            '${_describeTimer(current.clipboardAutoClearSeconds)} to '
            '${_describeTimer(restored.clipboardAutoClearSeconds)}.',
    ];

    await updateSettings(restored);

    return notes;
  }

  static String _describeTimer(int seconds) {
    if (seconds <= 0) return 'off';
    if (seconds < 60) return '$seconds seconds';

    return '${seconds ~/ 60} minutes';
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _edit((s) => s.copyWith(themeMode: mode));

  Future<void> setPalette(AppPalette palette) =>
      _edit((s) => s.copyWith(palette: palette));

  Future<void> setTerminalPalette(TerminalPalette palette) =>
      _edit((s) => s.copyWith(terminalPalette: palette));

  Future<void> setFontFamily(String fontFamily) =>
      _edit((s) => s.copyWith(fontFamily: fontFamily));

  Future<void> setUiFontFamily(String uiFontFamily) =>
      _edit((s) => s.copyWith(uiFontFamily: uiFontFamily));

  Future<void> setFontSize(double fontSize) =>
      _edit((s) => s.copyWith(fontSize: fontSize));

  /// One point bigger or smaller per press of the zoom shortcuts, held to the
  /// slider's range; a [step] of zero restores the default size.
  Future<void> stepFontSize(int step) async {
    final current = _base.fontSize;
    final next = step == 0
        ? const AppSettingsModel().fontSize
        : (current.roundToDouble() + step).clamp(
            kTerminalFontSizeMin,
            kTerminalFontSizeMax,
          );
    if (next == current) return;
    await setFontSize(next);
  }

  Future<void> setLineHeightFactor(double lineHeightFactor) =>
      _edit((s) => s.copyWith(lineHeightFactor: lineHeightFactor));

  Future<void> setCursorStyle(AppCursorStyle cursorStyle) =>
      _edit((s) => s.copyWith(cursorStyle: cursorStyle));

  Future<void> setEnableLigatures(bool enabled) =>
      _edit((s) => s.copyWith(enableLigatures: enabled));

  Future<void> setKeepRunningInTray(bool enabled) =>
      _edit((s) => s.copyWith(keepRunningInTray: enabled));

  Future<void> setDesktopNotifications(bool enabled) =>
      _edit((s) => s.copyWith(desktopNotifications: enabled));

  Future<void> setDrawBoldTextWithBrightColors(bool enabled) =>
      _edit((s) => s.copyWith(drawBoldTextWithBrightColors: enabled));

  Future<void> setMoshPrediction(MoshPredictionMode mode) =>
      _edit((s) => s.copyWith(moshPrediction: mode));

  Future<void> setAutoLockTimer(int seconds) =>
      _edit((s) => s.copyWith(autoLockTimerSeconds: seconds));

  Future<void> setClipboardAutoClear(int seconds) =>
      _edit((s) => s.copyWith(clipboardAutoClearSeconds: seconds));

  Future<void> setActiveWorkspace(String workspaceId) =>
      _edit((s) => s.copyWith(activeWorkspaceId: workspaceId));

  Future<void> _edit(AppSettingsModel Function(AppSettingsModel s) change) =>
      updateSettings(change(_base));
}
