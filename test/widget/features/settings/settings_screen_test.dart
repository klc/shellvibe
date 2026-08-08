import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:terly2/features/settings/presentation/screens/settings_screen.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('SettingsScreen Widget Tests', () {
    testWidgets('Renders SettingsScreen with all sections', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(home: SettingsScreen()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Wide layout: fixed section navigation, one section on screen at a time.
      for (final section in SettingsSection.values) {
        expect(
          find.byKey(Key('settings_section_${section.name}')),
          findsOneWidget,
        );
      }

      expect(find.text('App Theme & Appearance'), findsOneWidget);
      expect(
        find.byKey(const Key('settings_theme_mode_dropdown')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings_palette_dropdown')),
        findsOneWidget,
      );
      // Other sections are not rendered until their nav entry is selected.
      expect(
        find.byKey(const Key('settings_terminal_palette_dropdown')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('settings_section_terminal')));
      await tester.pumpAndSettle();
      expect(find.text('Terminal Theme & Shell'), findsOneWidget);
      expect(
        find.byKey(const Key('settings_terminal_palette_dropdown')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settings_mosh_prediction_dropdown')),
        findsOneWidget,
      );
      // Font, size and ligature changes are reflected in place; there is no
      // save step to confirm them against.
      expect(
        find.byKey(const Key('settings_terminal_preview')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('settings_section_security')));
      await tester.pumpAndSettle();
      expect(find.text('Security & Biometric Controls'), findsOneWidget);
      expect(find.byKey(const Key('test_biometrics_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings_section_sync')));
      await tester.pumpAndSettle();
      expect(find.text('Zero-Knowledge E2EE Cloud Sync'), findsOneWidget);
      expect(find.byKey(const Key('export_backup_button')), findsOneWidget);
    });

    testWidgets('Compact layout shows every section plus the tools group', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(home: SettingsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings & Preferences'), findsOneWidget);
      expect(
        find.byKey(const Key('settings_theme_mode_dropdown')),
        findsOneWidget,
      );
      // Modules without a mobile tab are reachable from here.
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings_tool_tunnels')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings_tool_tunnels')), findsOneWidget);
      expect(find.byKey(const Key('settings_tool_snippets')), findsOneWidget);
      expect(find.byKey(const Key('settings_tool_workspaces')), findsOneWidget);
    });
  });
}
