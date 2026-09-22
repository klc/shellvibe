import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/features/settings/presentation/screens/settings_screen.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

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

  /// The screen under a router, so section navigation is exercised the way the
  /// app does it: the open section is a route, not widget state.
  Widget buildApp({String initialLocation = '/settings'}) {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
          routes: [
            GoRoute(
              path: ':section',
              builder: (context, state) => SettingsScreen(
                section: SettingsSection.byName(
                  state.pathParameters['section'],
                ),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/tunnels',
          builder: (context, state) =>
              const Scaffold(body: Text('tunnels screen')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.light(),
          brightness: Brightness.light,
        ),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  group('SettingsScreen wide layout', () {
    testWidgets('Navigation column lists every section and opens one', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Wide layout: fixed section navigation, one section on screen at a time.
      for (final section in SettingsSection.values) {
        expect(
          find.byKey(Key('settings_section_${section.name}')),
          findsOneWidget,
        );
      }

      // With no section in the route the first one is open.
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
      // The nav column stays: a section is opened beside it, not on top of it.
      expect(
        find.byKey(const Key('settings_section_security')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings_section_back')), findsNothing);

      await tester.tap(find.byKey(const Key('settings_section_security')));
      await tester.pumpAndSettle();
      expect(find.text('Security & Biometric Controls'), findsOneWidget);
      expect(find.byKey(const Key('test_biometrics_button')), findsOneWidget);

      // Backup holds the copies the user takes: to their account, and to a
      // file. The file path keeps working with no account at all.
      await tester.tap(find.byKey(const Key('settings_section_backup')));
      await tester.pumpAndSettle();
      expect(find.text('Cloud Backup'), findsOneWidget);
      expect(find.text('Encrypted File Backup'), findsOneWidget);
      expect(find.byKey(const Key('export_backup_button')), findsOneWidget);

      // Sync is its own section. They shared a screen while automatic sync was
      // something a backup switched on; it is not that any more.
      await tester.tap(find.byKey(const Key('settings_section_sync')));
      await tester.pumpAndSettle();
      expect(find.text('Automatic Sync'), findsOneWidget);
      expect(find.byKey(const Key('auto_sync_enabled_switch')), findsOneWidget);
      expect(find.text('Encrypted File Backup'), findsNothing);
    });
  });

  group('SettingsScreen compact layout', () {
    testWidgets('Index lists the sections in groups and carries no controls', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);

      // Every section is one row of the index, under its group heading.
      for (final group in SettingsSectionGroup.values) {
        expect(find.text(group.label.toUpperCase()), findsOneWidget);
      }
      for (final section in SettingsSection.values) {
        await tester.scrollUntilVisible(
          find.byKey(Key('settings_section_${section.name}')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.byKey(Key('settings_section_${section.name}')),
          findsOneWidget,
        );
      }

      // The controls themselves are not on the index any more: that single
      // scroll of every setting the app has is what this replaced.
      expect(
        find.byKey(const Key('settings_theme_mode_dropdown')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('settings_terminal_palette_dropdown')),
        findsNothing,
      );

      // Modules without a mobile tab are reachable from here.
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings_tool_tunnels')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings_tool_tunnels')), findsOneWidget);
      expect(find.byKey(const Key('settings_tool_snippets')), findsOneWidget);
      expect(find.byKey(const Key('settings_tool_workspaces')), findsOneWidget);
    });

    testWidgets('Tapping a section opens its page, and back returns', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings_section_appearance')));
      await tester.pumpAndSettle();

      expect(find.text('App Theme & Appearance'), findsOneWidget);
      expect(
        find.byKey(const Key('settings_theme_mode_dropdown')),
        findsOneWidget,
      );
      // One section at a time: the rest of the index is gone.
      expect(find.byKey(const Key('settings_section_sync')), findsNothing);

      await tester.tap(find.byKey(const Key('settings_section_back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings_section_sync')), findsOneWidget);
      expect(
        find.byKey(const Key('settings_theme_mode_dropdown')),
        findsNothing,
      );
    });

    testWidgets('A deep link opens the section directly', (tester) async {
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildApp(initialLocation: '/settings/sync'));
      await tester.pumpAndSettle();

      expect(find.text('Automatic Sync'), findsOneWidget);
      expect(find.byKey(const Key('auto_sync_enabled_switch')), findsOneWidget);
    });
  });
}
