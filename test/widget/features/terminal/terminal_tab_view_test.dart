import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:terly2/core/utils/platform_capabilities.dart';
import 'package:terly2/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:terly2/features/terminal/presentation/views/terminal_tab_view.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    debugPlatformCapabilitiesOverride = null;
    await db.close();
  });

  Widget createWidgetUnderTest() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.dark(),
          brightness: Brightness.dark,
        ),
        child: const MaterialApp(
          home: TerminalTabView(),
        ),
      ),
    );
  }

  group('TerminalTabView Widget Tests', () {
    testWidgets('Renders empty state when no tabs are active', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('No Active Terminal Sessions'), findsOneWidget);
      expect(find.byKey(const Key('empty_open_local_button')), findsOneWidget);
      expect(find.byKey(const Key('empty_select_host_button')), findsOneWidget);
    });

    testWidgets('Does not expose or trigger a local shell on mobile', (tester) async {
      debugPlatformCapabilitiesOverride = TargetPlatform.android;
      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.dark(),
              brightness: Brightness.dark,
            ),
            child: const MaterialApp(home: TerminalTabView()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('empty_open_local_button')), findsNothing);
      expect(find.text('Select a remote SSH server to connect.'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(container.read(terminalTabsProvider).tabs, isEmpty);
    });

    testWidgets('Opens local shell tab on Open Local Shell button tap', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('empty_open_local_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Local Shell'), findsWidgets);
      expect(find.byKey(const Key('new_tab_button')), findsOneWidget);
    });
    testWidgets('Opens new tab menu on new tab button tap', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('new_tab_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('new_tab_menu_local')), findsOneWidget);
      expect(find.byKey(const Key('new_tab_menu_host')), findsOneWidget);
    });

    testWidgets('Closes active tab on close button tap', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const Key('empty_open_local_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Local Shell'), findsWidgets);

      final closeIcon = find.byIcon(Icons.close).first;
      await tester.tap(closeIcon);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const Key('empty_open_local_button')), findsOneWidget);
    });
  });
}
