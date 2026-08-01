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
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
          ],
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: SettingsScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Settings & Preferences'), findsOneWidget);
      expect(find.text('App Theme & Appearance'), findsOneWidget);
      expect(find.text('Terminal Theme & Shell'), findsOneWidget);
      expect(find.text('Security & Biometric Controls'), findsOneWidget);
      expect(find.text('Zero-Knowledge E2EE Cloud Sync'), findsOneWidget);

      expect(find.byKey(const Key('settings_theme_mode_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('settings_palette_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('settings_terminal_palette_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('test_biometrics_button')), findsOneWidget);
      expect(find.byKey(const Key('export_backup_button')), findsOneWidget);
    });
  });
}
