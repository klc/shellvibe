import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/app/app.dart';
import 'package:terly2/app/router/app_router.dart';
import 'package:terly2/core/network/local_pty_manager.dart';
import 'package:terly2/core/network/providers/network_providers.dart';
import 'package:terly2/features/settings/presentation/notifiers/settings_notifier.dart';
import 'package:terly2/features/terminal/domain/models/terminal_palette.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/providers/database_providers.dart';
import 'package:xterm3/xterm.dart';

class _NullPtyManager extends LocalPtyManager {
  @override
  TerminalLocalPtyBridge? startAndBridge(
    Terminal terminal, {
    String? executable,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 24,
    int columns = 80,
    void Function(Uint8List bytes)? outputTap,
  }) => null;
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
        child: const TerlyApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerlyApp)),
    );
    container.read(appRouterProvider).go('/settings');
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
}
