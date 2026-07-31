import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/hosts/presentation/screens/hosts_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/sftp/presentation/screens/sftp_dual_pane_screen.dart';
import '../../features/snippets/presentation/screens/snippets_screen.dart';
import '../../features/terminal/presentation/screens/terminal_tab_view.dart';
import '../../features/tunnels/presentation/screens/tunnels_screen.dart';
import '../../features/vault/presentation/screens/vault_screen.dart';
import '../widgets/app_navigation_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/hosts',
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => '/hosts',
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppNavigationShell(navigationShell: navigationShell);
        },
        branches: [
          // Index 0: Hosts
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/hosts',
                builder: (context, state) => const HostsScreen(),
              ),
            ],
          ),
          // Index 1: Terminal
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/terminal',
                builder: (context, state) => const TerminalTabView(),
              ),
            ],
          ),
          // Index 2: Vault
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/vault',
                builder: (context, state) => const VaultScreen(),
              ),
            ],
          ),
          // Index 3: SFTP
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sftp',
                builder: (context, state) => const SftpDualPaneScreen(),
              ),
            ],
          ),
          // Index 4: Tunnels
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tunnels',
                builder: (context, state) => const TunnelsScreen(),
              ),
            ],
          ),
          // Index 5: Snippets
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/snippets',
                builder: (context, state) => const SnippetsScreen(),
              ),
            ],
          ),
          // Index 6: Settings
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
