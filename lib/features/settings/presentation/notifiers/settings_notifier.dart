import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/providers/database_providers.dart';
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
    _lastKnown = updated;
    state = const AsyncValue.loading();
    final result = _writeChain.then((_) async {
      final repo = ref.read(settingsRepositoryProvider);
      await repo.saveSettings(updated);
      return updated;
    });
    _writeChain = result.then((_) {}, onError: (_) {});
    state = await AsyncValue.guard(() => result);
  }

  AppSettingsModel get _base =>
      _lastKnown ?? state.value ?? const AppSettingsModel();

  Future<void> setThemeMode(ThemeMode mode) async {
    final current = _base;
    await updateSettings(current.copyWith(themeMode: mode));
  }

  Future<void> setPalette(AppPalette palette) async {
    final current = _base;
    await updateSettings(current.copyWith(palette: palette));
  }

  Future<void> setTerminalPalette(TerminalPalette palette) async {
    final current = _base;
    await updateSettings(current.copyWith(terminalPalette: palette));
  }

  Future<void> setFontFamily(String fontFamily) async {
    final current = _base;
    await updateSettings(current.copyWith(fontFamily: fontFamily));
  }

  Future<void> setFontSize(double fontSize) async {
    final current = _base;
    await updateSettings(current.copyWith(fontSize: fontSize));
  }

  Future<void> setCursorStyle(AppCursorStyle cursorStyle) async {
    final current = _base;
    await updateSettings(current.copyWith(cursorStyle: cursorStyle));
  }

  Future<void> setAutoLockTimer(int seconds) async {
    final current = _base;
    await updateSettings(current.copyWith(autoLockTimerSeconds: seconds));
  }

  Future<void> setClipboardAutoClear(int seconds) async {
    final current = _base;
    await updateSettings(current.copyWith(clipboardAutoClearSeconds: seconds));
  }

  Future<void> setActiveWorkspace(String workspaceId) async {
    final current = _base;
    await updateSettings(current.copyWith(activeWorkspaceId: workspaceId));
  }
}
