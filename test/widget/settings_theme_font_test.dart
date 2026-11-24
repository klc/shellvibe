import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/app.dart';
import 'package:shellvibe/app/router/app_router.dart';
import 'package:shellvibe/app/theme/app_palette_definitions.dart';
import 'package:shellvibe/app/theme/shellvibe_tokens.dart';
import 'package:shellvibe/core/network/local_pty_manager.dart';
import 'package:shellvibe/core/network/providers/network_providers.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';
import 'package:shellvibe/features/settings/presentation/notifiers/settings_notifier.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_palette.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_palette_data.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:xterm3/xterm.dart';

class _NullPtyManager extends LocalPtyManager {
  @override
  Future<TerminalLocalPtyBridge?> startAndBridge(
    Terminal terminal, {
    String? executable,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 24,
    int columns = 80,
    void Function(Uint8List bytes)? outputTap,
  }) async => null;
}

void main() {
  testWidgets('settings shows registry-driven theme and font dropdowns '
      'with previews, and switching theme persists without error', (
    WidgetTester tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NullPtyManager()),
        ],
        child: const ShellVibeApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellVibeApp)),
    );
    // The terminal controls are a section of their own; on the compact tier
    // that section is a page of its own.
    container.read(appRouterProvider).go('/settings/terminal');
    await tester.pumpAndSettle();

    // Registry-driven dropdowns are wired.
    expect(
      find.byKey(const Key('settings_terminal_palette_dropdown')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('settings_font_family_dropdown')),
      findsOneWidget,
    );

    // Theme preview shows the default theme's sample command.
    expect(find.textContaining('ssh deploy'), findsOneWidget);
    // Font preview shows the ligature sample.
    expect(find.textContaining('== != =>'), findsOneWidget);

    // Open the theme dropdown: newly added themes are listed.
    await tester.ensureVisible(
      find.byKey(const Key('settings_terminal_palette_dropdown')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('settings_terminal_palette_dropdown')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rosé Pine'), findsOneWidget);
    expect(find.text('Kanagawa Wave'), findsOneWidget);
    expect(find.text('GitHub Dark Dimmed'), findsOneWidget);

    // Selecting a new theme applies it without exceptions.
    final popupList = find.byType(Scrollable).last;
    await tester.dragUntilVisible(
      find.text('Rosé Pine').last,
      popupList,
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rosé Pine').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      container.read(settingsProvider).value?.terminalPalette,
      TerminalPalette.rosePine,
    );
    expect(find.text('Current: Rosé Pine'), findsOneWidget);

    // Open the font dropdown: Nerd Font options are listed and marked.
    await tester.ensureVisible(
      find.byKey(const Key('settings_font_family_dropdown')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_font_family_dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('JetBrains Mono Nerd Font'), findsOneWidget);
    expect(find.text('MesloLGM Nerd Font'), findsOneWidget);
    expect(find.text('Hack Nerd Font'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('JetBrains Mono Nerd Font').last,
      find.byType(Scrollable).last,
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('JetBrains Mono Nerd Font').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      container.read(settingsProvider).value?.fontFamily,
      'JetBrainsMonoNF',
    );

    // Line height slider is wired: dragging persists a new factor.
    final lineHeightSlider = find.byKey(
      const Key('settings_line_height_slider'),
    );
    await tester.ensureVisible(lineHeightSlider);
    await tester.pumpAndSettle();
    expect(lineHeightSlider, findsOneWidget);
    expect(container.read(settingsProvider).value?.lineHeightFactor, 1.4);
    await tester.drag(lineHeightSlider, const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(container.read(settingsProvider).value?.lineHeightFactor, 2.0);
  });

  Future<ProviderContainer> openSettings(
    WidgetTester tester,
    String section,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NullPtyManager()),
        ],
        child: const ShellVibeApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellVibeApp)),
    );
    container.read(appRouterProvider).go('/settings/$section');
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> openDropdown(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pumpAndSettle();
    return mouse;
  }

  testWidgets('pointing at a terminal scheme previews it until the list '
      'closes, without saving it', (tester) async {
    final container = await openSettings(tester, 'terminal');
    Color? previewForeground() =>
        tester.widget<Text>(find.textContaining('ssh deploy')).style?.color;
    final stored = previewForeground();
    final rosePine = TerminalPaletteData.of(TerminalPalette.rosePine).theme;

    await openDropdown(tester, 'settings_terminal_palette_dropdown');
    await tester.dragUntilVisible(
      find.text('Rosé Pine').last,
      find.byType(Scrollable).last,
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    final mouse = await hover(tester, find.text('Rosé Pine').last);

    expect(previewForeground(), rosePine.foreground);
    expect(
      container.read(settingsProvider).value?.terminalPalette,
      const AppSettingsModel().terminalPalette,
    );

    await mouse.moveTo(Offset.zero);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(previewForeground(), stored);
  });

  testWidgets('moving through the schemes with the keyboard previews each '
      'one', (tester) async {
    await openSettings(tester, 'terminal');
    Color? previewForeground() =>
        tester.widget<Text>(find.textContaining('ssh deploy')).style?.color;

    await openDropdown(tester, 'settings_terminal_palette_dropdown');
    // The list opens on the saved scheme; the next one down is the first in
    // the registry after it.
    final order = [
      TerminalPalette.matchApp,
      ...kTerminalPalettes.map((p) => p.palette),
    ];
    final next =
        order[order.indexOf(const AppSettingsModel().terminalPalette) + 1];

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(previewForeground(), TerminalPaletteData.of(next).theme.foreground);
  });

  testWidgets('pointing at an app palette themes the app with it until the '
      'list closes, without saving it', (tester) async {
    final container = await openSettings(tester, 'appearance');

    await openDropdown(tester, 'settings_palette_dropdown');
    final mouse = await hover(tester, find.text(AppPalette.nord.label).last);

    expect(container.read(appPalettePreviewProvider), AppPalette.nord);
    final context = tester.element(
      find.byKey(const Key('settings_palette_dropdown')),
    );
    final nord = AppPaletteDefinition.forPalette(AppPalette.nord);
    expect(
      ShellVibeTokens.resolve(context).canvas,
      Theme.of(context).brightness == Brightness.dark
          ? nord.darkTokens.canvas
          : nord.lightTokens.canvas,
    );
    expect(
      container.read(settingsProvider).value?.palette,
      const AppSettingsModel().palette,
    );

    await mouse.moveTo(Offset.zero);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(container.read(appPalettePreviewProvider), isNull);
    expect(tester.takeException(), isNull);
  });
}
