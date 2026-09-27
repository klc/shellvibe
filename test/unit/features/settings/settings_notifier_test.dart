import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/models/mosh_prediction_mode.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';
import 'package:shellvibe/features/settings/presentation/notifiers/settings_notifier.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_palette.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('a changed setting is still there on the next launch', () async {
    // Each setter goes through the repository, not just into memory. A setter
    // that only updated state would look right until the app restarted.
    final first = ProviderContainer();
    await first.read(settingsProvider.future);
    final notifier = first.read(settingsProvider.notifier);

    await notifier.setThemeMode(ThemeMode.light);
    await notifier.setPalette(AppPalette.nord);
    await notifier.setTerminalPalette(TerminalPalette.dracula);
    await notifier.setFontSize(16);
    await notifier.setCursorStyle(AppCursorStyle.underline);
    await notifier.setAutoLockTimer(600);
    await notifier.setMoshPrediction(MoshPredictionMode.never);
    first.dispose();

    final second = ProviderContainer();
    addTearDown(second.dispose);
    final restored = await second.read(settingsProvider.future);

    expect(restored.themeMode, ThemeMode.light);
    expect(restored.palette, AppPalette.nord);
    expect(restored.terminalPalette, TerminalPalette.dracula);
    expect(restored.fontSize, 16);
    expect(restored.cursorStyle, AppCursorStyle.underline);
    expect(restored.autoLockTimerSeconds, 600);
    expect(restored.moshPrediction, MoshPredictionMode.never);
  });
}
