import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

@riverpod
ClipboardAutoClearService clipboardAutoClearService(Ref ref) {
  return ClipboardAutoClearService();
}

@riverpod
class SettingsNotifier extends _$SettingsNotifier {
  @override
  Future<AppSettingsModel> build() async {
    final repo = ref.watch(settingsRepositoryProvider);
    return await repo.loadSettings();
  }

  Future<void> updateSettings(AppSettingsModel updated) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(settingsRepositoryProvider);
      await repo.saveSettings(updated);
      return updated;
    });
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final current = state.value ?? const AppSettingsModel();
    await updateSettings(current.copyWith(themeMode: mode));
  }

  Future<void> setPalette(AppPalette palette) async {
    final current = state.value ?? const AppSettingsModel();
    await updateSettings(current.copyWith(palette: palette));
  }

  Future<void> setFontFamily(String fontFamily) async {
    final current = state.value ?? const AppSettingsModel();
    await updateSettings(current.copyWith(fontFamily: fontFamily));
  }

  Future<void> setFontSize(double fontSize) async {
    final current = state.value ?? const AppSettingsModel();
    await updateSettings(current.copyWith(fontSize: fontSize));
  }

  Future<void> setCursorStyle(AppCursorStyle cursorStyle) async {
    final current = state.value ?? const AppSettingsModel();
    await updateSettings(current.copyWith(cursorStyle: cursorStyle));
  }

  Future<void> setAutoLockTimer(int seconds) async {
    final current = state.value ?? const AppSettingsModel();
    await updateSettings(current.copyWith(autoLockTimerSeconds: seconds));
  }

  Future<void> setClipboardAutoClear(int seconds) async {
    final current = state.value ?? const AppSettingsModel();
    await updateSettings(current.copyWith(clipboardAutoClearSeconds: seconds));
  }
}
