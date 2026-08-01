import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/hosts/presentation/screens/hosts_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/sftp/presentation/screens/sftp_dual_pane_screen.dart';
import '../../features/snippets/presentation/screens/snippets_screen.dart';
import '../../features/terminal/presentation/screens/terminal_tab_view.dart';
import '../../features/tunnels/presentation/screens/tunnels_screen.dart';
import '../../features/vault/presentation/dialogs/vault_unlock_dialog.dart';
import '../../features/vault/presentation/notifiers/vault_notifier.dart';
import '../../features/vault/presentation/screens/vault_screen.dart';
import '../widgets/app_navigation_shell.dart';

/// Route showing the master password prompt while the vault is locked.
const kUnlockRoute = '/unlock';

/// Decides where the vault state forces navigation to, or null to stay put.
///
/// [status] is null while [vaultNotifierProvider] is still resolving — which
/// also happens *during* an unlock attempt, so a null status must never bounce
/// the user off the unlock screen mid-verification.
String? resolveVaultRedirect(VaultStatus? status, String location) {
  final isAtUnlock = location == kUnlockRoute;

  if (status == VaultStatus.locked) return isAtUnlock ? null : kUnlockRoute;
  if (isAtUnlock && status == null) return null;
  if (isAtUnlock) return '/hosts';
  return null;
}

/// Notifier that triggers GoRouter redirect re-evaluation
/// whenever the vault state changes.
class _VaultRouterNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final vaultRouterNotifier = _VaultRouterNotifier();

  ref.listen(vaultNotifierProvider, (_, _) {
    vaultRouterNotifier.notify();
  });
  ref.onDispose(vaultRouterNotifier.dispose);

  return GoRouter(
    initialLocation: '/hosts',
    refreshListenable: vaultRouterNotifier,
    // Gate the whole app behind the unlock screen while the vault is locked.
    // Without this the master password would never be asked for.
    redirect: (context, state) => resolveVaultRedirect(
      ref.read(vaultNotifierProvider).valueOrNull?.status,
      state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => '/hosts',
      ),
      GoRoute(
        path: kUnlockRoute,
        builder: (context, state) => const VaultUnlockDialog(),
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
