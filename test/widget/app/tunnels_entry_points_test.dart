import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/app/router/app_router.dart';
import 'package:shellvibe/app/widgets/app_navigation_shell.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/settings/presentation/screens/settings_screen.dart';
import 'package:shellvibe/features/tunnels/presentation/screens/tunnels_screen.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/vault_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

/// Where a tunnel can be reached from, per device: hidden on an iPhone (the
/// socket dies with the app), kept elsewhere, with a hint on an iPad.
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

  /// [display] is the physical screen and [window] what the app is given of
  /// it; they differ in Split View and Stage Manager.
  Future<void> pumpApp(
    WidgetTester tester, {
    required TargetPlatform platform,
    required Size display,
    Size? window,
  }) async {
    debugPlatformCapabilitiesOverride = platform;
    tester.view.physicalSize = window ?? display;
    tester.view.devicePixelRatio = 1.0;
    tester.view.display.size = display;
    tester.view.display.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.display.resetSize();
      tester.view.display.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          vaultProvider.overrideWith(_UnlockedVault.new),
        ],
        child: Consumer(
          builder: (context, ref, _) => ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: MaterialApp.router(
              routerConfig: ref.watch(appRouterProvider),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('mobile_nav_destination_settings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  const iPhone = Size(390, 844);
  const iPhoneLandscape = Size(844, 390);
  const iPad = Size(1180, 820);

  group('iPhone', () {
    testWidgets('the Settings tools list offers no Tunnels', (tester) async {
      await pumpApp(tester, platform: TargetPlatform.iOS, display: iPhone);
      await openSettings(tester);

      await tester.scrollUntilVisible(
        find.byKey(const Key('settings_tool_snippets')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('settings_tool_snippets')), findsOneWidget);
      expect(find.byKey(const Key('settings_tool_workspaces')), findsOneWidget);
      expect(find.byKey(const Key('settings_tool_tunnels')), findsNothing);
    });

    testWidgets('the command palette lists no Tunnels module', (tester) async {
      await pumpApp(tester, platform: TargetPlatform.iOS, display: iPhone);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(find.text('Snippets'), findsOneWidget, reason: 'palette is open');
      expect(find.text('Tunnels'), findsNothing);
    });

    testWidgets('a hardware-keyboard Cmd+4 does not reach Tunnels', (
      tester,
    ) async {
      await pumpApp(tester, platform: TargetPlatform.iOS, display: iPhone);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(find.byType(TunnelsScreen), findsNothing);
    });

    testWidgets('held sideways it is still an iPhone', (tester) async {
      await pumpApp(
        tester,
        platform: TargetPlatform.iOS,
        display: iPhoneLandscape,
      );
      await openSettings(tester);

      await tester.scrollUntilVisible(
        find.byKey(const Key('settings_tool_snippets')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('settings_tool_tunnels')), findsNothing);
    });
  });

  group('iPad', () {
    testWidgets('the rail keeps Tunnels and the screen carries the hint', (
      tester,
    ) async {
      await pumpApp(tester, platform: TargetPlatform.iOS, display: iPad);

      final tunnelsIndex = navigationIndexForPath('/tunnels');
      expect(find.byKey(Key('nav_item_$tunnelsIndex')), findsOneWidget);

      await tester.tap(find.byKey(Key('nav_item_$tunnelsIndex')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TunnelsScreen), findsOneWidget);
      expect(find.byKey(const Key('tunnels_foreground_hint')), findsOneWidget);
      expect(
        find.textContaining('Split View or Stage Manager'),
        findsOneWidget,
      );
    });

    testWidgets('the hint can be dismissed and stays away', (tester) async {
      await pumpApp(tester, platform: TargetPlatform.iOS, display: iPad);
      await tester.tap(
        find.byKey(Key('nav_item_${navigationIndexForPath('/tunnels')}')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(
        find.byKey(const Key('tunnels_foreground_hint_dismiss')),
      );
      await tester.pump();
      expect(find.byKey(const Key('tunnels_foreground_hint')), findsNothing);

      // Away and back: still dismissed for the run.
      await tester.tap(find.byKey(const Key('nav_item_0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(Key('nav_item_${navigationIndexForPath('/tunnels')}')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TunnelsScreen), findsOneWidget);
      expect(find.byKey(const Key('tunnels_foreground_hint')), findsNothing);
    });
  });

  group('iPad in a narrow window', () {
    // The device class is the screen's, not the window's: a third of Split
    // View is as narrow as an iPhone and is when a tunnel is most wanted.
    const ipadDisplay = Size(1024, 1366);
    const thirdOfSplitView = Size(320, 1000);

    testWidgets('keeps Tunnels in Settings and shows the hint', (tester) async {
      await pumpApp(
        tester,
        platform: TargetPlatform.iOS,
        display: ipadDisplay,
        window: thirdOfSplitView,
      );
      await openSettings(tester);

      await tester.scrollUntilVisible(
        find.byKey(const Key('settings_tool_tunnels')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // scrollUntilVisible stops as soon as the row enters the viewport, which
      // can be under the floating tab bar; scroll on so the tap lands on it.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings_tool_tunnels')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TunnelsScreen), findsOneWidget);
      expect(find.byKey(const Key('tunnels_foreground_hint')), findsOneWidget);
    });

    testWidgets('an iPhone display with the same window still hides it', (
      tester,
    ) async {
      await pumpApp(
        tester,
        platform: TargetPlatform.iOS,
        display: iPhone,
        window: const Size(390, 700),
      );
      await openSettings(tester);

      await tester.scrollUntilVisible(
        find.byKey(const Key('settings_tool_snippets')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('settings_tool_tunnels')), findsNothing);
    });
  });

  group('route guard', () {
    GoRouter routerOf(WidgetTester tester) => ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    ).read(appRouterProvider);

    testWidgets('a link to /tunnels on an iPhone lands on Settings', (
      tester,
    ) async {
      await pumpApp(tester, platform: TargetPlatform.iOS, display: iPhone);

      routerOf(tester).go('/tunnels');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TunnelsScreen), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('an iPad reaches /tunnels', (tester) async {
      await pumpApp(tester, platform: TargetPlatform.iOS, display: iPad);

      routerOf(tester).go('/tunnels');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TunnelsScreen), findsOneWidget);
    });

    testWidgets('an iPad in a narrow window reaches /tunnels', (tester) async {
      await pumpApp(
        tester,
        platform: TargetPlatform.iOS,
        display: const Size(1024, 1366),
        window: const Size(320, 1000),
      );

      routerOf(tester).go('/tunnels');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TunnelsScreen), findsOneWidget);
    });

    testWidgets('Android is not redirected', (tester) async {
      await pumpApp(tester, platform: TargetPlatform.android, display: iPhone);

      routerOf(tester).go('/tunnels');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TunnelsScreen), findsOneWidget);
    });
  });

  group('Android', () {
    testWidgets('keeps Tunnels on a phone, with no iPad hint', (tester) async {
      await pumpApp(tester, platform: TargetPlatform.android, display: iPhone);
      await openSettings(tester);

      await tester.scrollUntilVisible(
        find.byKey(const Key('settings_tool_tunnels')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('settings_tool_tunnels')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TunnelsScreen), findsOneWidget);
      expect(find.byKey(const Key('tunnels_foreground_hint')), findsNothing);
    });
  });
}

class _UnlockedVault extends VaultNotifier {
  @override
  Future<VaultState> build() async =>
      const VaultState(status: VaultStatus.unlocked);
}
