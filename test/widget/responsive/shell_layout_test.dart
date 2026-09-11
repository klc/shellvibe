import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/app/router/app_router.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

/// Which navigation the shell picks, at the sizes that used to fool it.
///
/// The rail decision used to read screen width alone, which made a phone held
/// sideways — 852px wide, 393px tall — look like a desktop and hand a thumb a
/// vertical icon rail advertising ⌘ shortcuts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'default',
        name: 'Default Workspace',
        createdAt: DateTime.now(),
      ),
    );
  });

  tearDown(() async {
    debugPlatformCapabilitiesOverride = null;
    await db.close();
  });

  Widget createShell() {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: Consumer(
        builder: (context, ref, _) {
          final router = ref.watch(appRouterProvider);
          return ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.dark(),
              brightness: Brightness.dark,
            ),
            child: MaterialApp.router(routerConfig: router),
          );
        },
      ),
    );
  }

  Future<bool> pumpAndReadUsesRail(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(createShell());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final hasTabBar = find
        .byKey(const Key('mobile_bottom_navigation_bar'))
        .evaluate()
        .isNotEmpty;
    final hasRail = find
        .byKey(const Key('command_palette_button'))
        .evaluate()
        .isNotEmpty;
    expect(
      hasTabBar != hasRail,
      isTrue,
      reason: 'exactly one navigation must be shown',
    );
    return hasRail;
  }

  testWidgets('a phone in landscape keeps the tab bar', (tester) async {
    debugPlatformCapabilitiesOverride = TargetPlatform.iOS;
    expect(
      await pumpAndReadUsesRail(tester, const Size(852, 393)),
      isFalse,
      reason: '852px wide but only 393px tall is a phone, not a desktop',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone in portrait keeps the tab bar', (tester) async {
    debugPlatformCapabilitiesOverride = TargetPlatform.iOS;
    expect(await pumpAndReadUsesRail(tester, const Size(393, 852)), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tablet earns the rail', (tester) async {
    debugPlatformCapabilitiesOverride = TargetPlatform.iOS;
    expect(await pumpAndReadUsesRail(tester, const Size(834, 1194)), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a desktop window earns the rail', (tester) async {
    expect(await pumpAndReadUsesRail(tester, const Size(1440, 900)), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrowed desktop window falls back to the tab bar', (
    tester,
  ) async {
    expect(await pumpAndReadUsesRail(tester, const Size(600, 900)), isFalse);
    expect(tester.takeException(), isNull);
  });
}
