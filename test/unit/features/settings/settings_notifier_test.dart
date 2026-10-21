import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/models/mosh_prediction_mode.dart';
import 'package:shellvibe/features/settings/data/repositories/settings_repository.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';
import 'package:shellvibe/features/settings/presentation/notifiers/settings_notifier.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_palette.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

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

  test('a change never puts the provider into loading', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);

    final seen = <AsyncValue<AppSettingsModel>>[];
    container.listen(settingsProvider, (_, next) => seen.add(next));

    await container.read(settingsProvider.notifier).setFontSize(16);

    expect(seen, isNotEmpty);
    expect(seen.any((s) => s.isLoading), isFalse);
    expect(seen.last.value!.fontSize, 16);
  });

  test('a failed write throws and restores the stored value', () async {
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(_FailingRepository()),
      ],
    );
    addTearDown(container.dispose);
    final before = await container.read(settingsProvider.future);
    final notifier = container.read(settingsProvider.notifier);

    await expectLater(notifier.setFontSize(16), throwsA(isA<StateError>()));

    final state = container.read(settingsProvider);
    expect(state.hasValue, isTrue);
    expect(state.hasError, isFalse);
    expect(state.value!.fontSize, before.fontSize);
  });

  test('a failed write does not undo a newer edit queued behind it', () async {
    final repo = _FailsFirstRepository();
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    final notifier = container.read(settingsProvider.notifier);

    final failed = notifier.setFontSize(16);
    final later = notifier.setThemeMode(ThemeMode.light);
    await expectLater(failed, throwsA(isA<StateError>()));
    await later;

    // The second write stored both changes; the page must show that.
    final shown = container.read(settingsProvider).value!;
    expect(repo.saved!.fontSize, 16);
    expect(shown.fontSize, 16);
    expect(shown.themeMode, ThemeMode.light);
  });
}

class _FailingRepository extends SettingsRepository {
  _FailingRepository() : super(SecureStorageService());

  @override
  Future<void> saveSettings(AppSettingsModel settings) async =>
      throw StateError('storage refused');
}

class _FailsFirstRepository extends SettingsRepository {
  _FailsFirstRepository() : super(SecureStorageService());

  var _calls = 0;
  AppSettingsModel? saved;

  @override
  Future<void> saveSettings(AppSettingsModel settings) async {
    if (_calls++ == 0) throw StateError('storage refused');
    saved = settings;
  }
}
