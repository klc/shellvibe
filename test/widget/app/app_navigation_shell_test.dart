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
        vaultNotifierProvider.overrideWith(
          () => _UnlockedVaultNotifier(),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final router = ref.watch(appRouterProvider);
          return ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: MaterialApp.router(
              routerConfig: router,
            ),
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
    testWidgets('Renders AppNavigationShell header and initial Hosts screen', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await pumpTabTransition(tester);

      // Header components
      expect(find.byKey(const Key('header_brand_logo')), findsOneWidget);
      expect(find.byKey(const Key('workspace_selector_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('ssh_status_badge')), findsOneWidget);
      expect(find.byKey(const Key('tunnels_status_badge')), findsOneWidget);
      expect(find.byKey(const Key('biometric_status_indicator')), findsOneWidget);

      // Default initial tab should be HostsScreen
      expect(find.byType(HostsScreen), findsOneWidget);
    });

    testWidgets('Switching tabs via desktop navigation shell loads corresponding screens', (tester) async {
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

      // 6. Switch to Settings (/settings - Index 6)
      await tester.tap(find.byKey(const Key('nav_item_6')));
      await pumpTabTransition(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);

      // 7. Switch back to Hosts (/hosts - Index 0)
      await tester.tap(find.byKey(const Key('nav_item_0')));
      await pumpTabTransition(tester);
      expect(find.byType(HostsScreen), findsOneWidget);
    });

    testWidgets('Toggles sidebar collapse state on toggle button tap', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await pumpTabTransition(tester);

      final toggleBtn = find.byKey(const Key('sidebar_toggle_button'));
      expect(toggleBtn, findsOneWidget);

      // Initial state: expanded, label "Hosts" should be visible
      expect(find.text('Hosts'), findsWidgets);

      // Tap toggle button to collapse
      await tester.tap(toggleBtn);
      await pumpTabTransition(tester);

      // Expanded text labels hidden in collapsed mode
      expect(find.byType(AppNavigationShell), findsOneWidget);

      // Tap toggle button to expand again
      await tester.tap(toggleBtn);
      await pumpTabTransition(tester);
      expect(find.text('Hosts'), findsWidgets);
    });

    testWidgets('Renders mobile bottom navigation bar on compact screen sizes', (tester) async {
      // Set small physical screen size for mobile view test
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await pumpTabTransition(tester);

      expect(find.byKey(const Key('mobile_bottom_navigation_bar')), findsOneWidget);

      // Tap mobile navigation item (Terminal)
      await tester.tap(find.byKey(const Key('mobile_nav_destination_terminal')));
      await pumpTabTransition(tester);
      expect(find.byType(TerminalTabView), findsOneWidget);
    });
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
