import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/hosts/presentation/screens/hosts_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/sftp/presentation/screens/sftp_dual_pane_screen.dart';
import '../../features/snippets/presentation/screens/snippets_screen.dart';
import '../../features/terminal/presentation/screens/terminal_tab_view.dart';
import '../../features/tunnels/presentation/screens/tunnels_screen.dart';
import '../../features/vault/presentation/notifiers/vault_notifier.dart';
import '../../features/vault/presentation/screens/vault_screen.dart';
import '../widgets/app_navigation_shell.dart';

/// Notifier that triggers GoRouter redirect re-evaluation
/// whenever the vault state changes.
class _VaultRouterNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final vaultRouterNotifier = _VaultRouterNotifier();

  // Re-evaluate redirects whenever vault state changes
  ref.listen(vaultNotifierProvider, (_, _) {
    vaultRouterNotifier.notify();
  });
  ref.onDispose(vaultRouterNotifier.dispose);

  return GoRouter(
    initialLocation: '/hosts',
    refreshListenable: vaultRouterNotifier,
    redirect: (context, state) {
      final vaultAsync = ref.read(vaultNotifierProvider);
      final vaultStatus = vaultAsync.valueOrNull?.status;
      final isVaultRoute = state.matchedLocation == '/vault';

      // Still loading vault state — don't redirect yet
      if (vaultAsync.isLoading) return null;

      // Vault is not unlocked and user is not on the vault page → force to vault
      if (vaultStatus != VaultStatus.unlocked && !isVaultRoute) {
        return '/vault';
      }

      // Vault is unlocked and user is on the vault page → go to hosts
      if (vaultStatus == VaultStatus.unlocked && isVaultRoute) {
        return '/hosts';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => '/hosts',
      ),
      // Vault route lives outside the shell so it can be shown full-screen
      GoRoute(
        path: '/vault',
        builder: (context, state) => const VaultScreen(),
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
          // Index 2: SFTP
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sftp',
                builder: (context, state) => const SftpDualPaneScreen(),
              ),
            ],
          ),
          // Index 3: Tunnels
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tunnels',
                builder: (context, state) => const TunnelsScreen(),
              ),
            ],
          ),
          // Index 4: Snippets
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/snippets',
                builder: (context, state) => const SnippetsScreen(),
              ),
            ],
          ),
          // Index 5: Settings
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
