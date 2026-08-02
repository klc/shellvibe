import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:terly2/app/router/app_router.dart';
import 'package:terly2/app/widgets/app_navigation_shell.dart';
import 'package:terly2/features/hosts/presentation/screens/hosts_screen.dart';
import 'package:terly2/features/settings/presentation/screens/settings_screen.dart';
import 'package:terly2/features/sftp/presentation/screens/sftp_dual_pane_screen.dart';
import 'package:terly2/features/snippets/presentation/screens/snippets_screen.dart';
import 'package:terly2/features/terminal/presentation/views/terminal_tab_view.dart';
import 'package:terly2/features/tunnels/presentation/screens/tunnels_screen.dart';
import 'package:terly2/features/vault/presentation/notifiers/vault_notifier.dart';
import 'package:terly2/features/vault/presentation/screens/vault_screen.dart';
import 'package:terly2/features/workspaces/presentation/screens/workspace_manager_screen.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/providers/database_providers.dart';

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
    await db.close();
  });

  Widget createTestWidget() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        vaultProvider.overrideWith(() => _UnlockedVaultNotifier()),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final router = ref.watch(appRouterProvider);
          return ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: MaterialApp.router(routerConfig: router),
          );
        },
      ),
    );
  }

  Future<void> pumpTabTransition(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('AppNavigationShell & GoRouter Integration Tests', () {
    testWidgets('Renders the persistent rail and the initial Hosts screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await pumpTabTransition(tester);

      // The rail is the whole desktop chrome: brand, command palette entry,
      // live status badges and the workspace avatar all live on it.
      expect(find.byKey(const Key('header_brand_logo')), findsOneWidget);
      expect(find.byKey(const Key('command_palette_button')), findsOneWidget);
      expect(find.byKey(const Key('ssh_status_badge')), findsOneWidget);
      expect(find.byKey(const Key('tunnels_status_badge')), findsOneWidget);
      expect(
        find.byKey(const Key('biometric_status_indicator')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('workspace_avatar_button')), findsOneWidget);

      // The workspace switcher moved into the module's context column.
      expect(
        find.byKey(const Key('workspace_selector_dropdown')),
        findsOneWidget,
      );

      // Default initial tab should be HostsScreen
      expect(find.byType(HostsScreen), findsOneWidget);
    });

    testWidgets('Rail renders the wireframe module order', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await pumpTabTransition(tester);

      final railPaths = kRailLayout.whereType<String>().toList();
      final renderedOrder = railPaths
          .map(
            (path) => tester.getTopLeft(
              find.byKey(Key('nav_item_${navigationIndexForPath(path)}')),
            ),
          )
          .toList();

      for (var i = 1; i < renderedOrder.length; i++) {
        expect(
          renderedOrder[i].dy,
          greaterThan(renderedOrder[i - 1].dy),
          reason: 'rail order must follow kRailLayout',
        );
      }
    });

    testWidgets(
      'Switching tabs via desktop navigation shell loads corresponding screens',
      (tester) async {
        await tester.pumpWidget(createTestWidget());
        await pumpTabTransition(tester);

        // 1. Switch to Terminal (/terminal - Index 1)
        await tester.tap(find.byKey(const Key('nav_item_1')));
        await pumpTabTransition(tester);
        expect(find.byType(TerminalTabView), findsOneWidget);

        // 2. Switch to Vault (/vault - Index 2)
        await tester.tap(find.byKey(const Key('nav_item_2')));
        await pumpTabTransition(tester);
        expect(find.byType(VaultScreen), findsOneWidget);

        // 3. Switch to SFTP (/sftp - Index 3)
        await tester.tap(find.byKey(const Key('nav_item_3')));
        await pumpTabTransition(tester);
        expect(find.byType(SftpDualPaneScreen), findsOneWidget);

        // 4. Switch to Tunnels (/tunnels - Index 4)
        await tester.tap(find.byKey(const Key('nav_item_4')));
        await pumpTabTransition(tester);
        expect(find.byType(TunnelsScreen), findsOneWidget);

        // 5. Switch to Snippets (/snippets - Index 5)
        await tester.tap(find.byKey(const Key('nav_item_5')));
        await pumpTabTransition(tester);
        expect(find.byType(SnippetsScreen), findsOneWidget);

        // 6. Switch to Workspaces (/workspaces - Index 6)
        await tester.tap(find.byKey(const Key('nav_item_6')));
        await pumpTabTransition(tester);
        expect(find.byType(WorkspaceManagerScreen), findsOneWidget);

        // 7. Switch to Settings (/settings - Index 7)
        await tester.tap(find.byKey(const Key('nav_item_7')));
        await pumpTabTransition(tester);
        expect(find.byType(SettingsScreen), findsOneWidget);

        // 7. Switch back to Hosts (/hosts - Index 0)
        await tester.tap(find.byKey(const Key('nav_item_0')));
        await pumpTabTransition(tester);
        expect(find.byType(HostsScreen), findsOneWidget);
      },
    );

    testWidgets('Rail is icon-only and has no collapse toggle', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await pumpTabTransition(tester);

      // Labels live in the context column now, so the rail has a fixed width
      // and the collapse affordance is gone.
      expect(find.byKey(const Key('sidebar_toggle_button')), findsNothing);
      expect(find.byType(AppNavigationShell), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('nav_item_0'))).width,
        lessThan(56),
      );
    });

    testWidgets(
      'Renders mobile bottom navigation bar on compact screen sizes',
      (tester) async {
        // Set small physical screen size for mobile view test
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createTestWidget());
        await pumpTabTransition(tester);

        expect(
          find.byKey(const Key('mobile_bottom_navigation_bar')),
          findsOneWidget,
        );

        // Tap mobile navigation item (Terminal)
        await tester.tap(
          find.byKey(const Key('mobile_nav_destination_terminal')),
        );
        await pumpTabTransition(tester);
        expect(find.byType(TerminalTabView), findsOneWidget);
      },
    );

    testWidgets(
      'Mobile navigation exposes the five wireframe tabs in rail order',
      (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createTestWidget());
        await pumpTabTransition(tester);

        // Vault and Settings are first-class tabs rather than sheet entries.
        expect(find.byType(NavigationDestination), findsNWidgets(5));
        for (final path in kMobileTabPaths) {
          expect(
            find.byKey(Key('mobile_nav_destination_${path.substring(1)}')),
            findsOneWidget,
          );
        }

        await tester.tap(find.byKey(const Key('mobile_nav_destination_vault')));
        await pumpTabTransition(tester);
        expect(find.byType(VaultScreen), findsOneWidget);
      },
    );

    testWidgets('Command palette opens from desktop shell', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await pumpTabTransition(tester);

      await tester.tap(find.byKey(const Key('command_palette_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('command_palette_search')), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
    });

    // Every module at every breakpoint. The initial route alone used to be
    // covered, which is exactly where the layout overflows were not.
    for (final width in [375.0, 768.0, 1024.0, 1440.0]) {
      testWidgets('Every module lays out cleanly at ${width.toInt()} px', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createTestWidget());
        await pumpTabTransition(tester);
        expect(tester.takeException(), isNull, reason: 'initial route');

        final isCompact =
            find.byKey(const Key('mobile_bottom_navigation_bar')).evaluate().isNotEmpty;

        if (isCompact) {
          for (final path in kMobileTabPaths) {
            await tester.tap(
              find.byKey(Key('mobile_nav_destination_${path.substring(1)}')),
            );
            await pumpTabTransition(tester);
            expect(tester.takeException(), isNull, reason: path);
          }
        } else {
          for (final path in kRailLayout.whereType<String>()) {
            await tester.tap(
              find.byKey(Key('nav_item_${navigationIndexForPath(path)}')),
            );
            await pumpTabTransition(tester);
            expect(tester.takeException(), isNull, reason: path);
          }
        }
      });
    }
  });
}

/// Test-only notifier that immediately provides an unlocked vault state,
/// bypassing the vault guard redirect in router tests.
class _UnlockedVaultNotifier extends VaultNotifier {
  @override
  Future<VaultState> build() async {
    return const VaultState(status: VaultStatus.unlocked);
  }
}
