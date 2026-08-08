import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/device_link/device_link_server.dart';
import '../../features/device_link/presentation/screens/pairing_qr_screen.dart';
import '../../features/device_link/presentation/screens/scan_pair_screen.dart';
import '../../features/hosts/presentation/screens/hosts_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/sftp/presentation/screens/sftp_dual_pane_screen.dart';
import '../../features/snippets/presentation/screens/snippets_screen.dart';
import '../../features/terminal/presentation/views/terminal_tab_view.dart';
import '../../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../features/tunnels/presentation/screens/tunnels_screen.dart';
import '../../features/vault/presentation/dialogs/vault_unlock_dialog.dart';
import '../../features/vault/presentation/notifiers/vault_notifier.dart';
import '../../features/vault/presentation/screens/vault_screen.dart';
import '../../features/workspaces/presentation/screens/workspace_manager_screen.dart';
import '../widgets/app_navigation_shell.dart';

/// Route showing the master password prompt while the vault is locked.
const kUnlockRoute = '/unlock';

/// Decides where the vault state forces navigation to, or null to stay put.
///
/// [status] is null while [vaultProvider] is still resolving — which
/// also happens *during* an unlock attempt, so a null status must never bounce
/// the user off the unlock screen mid-verification.
String? resolveVaultRedirect(VaultStatus? status, String location) {
  final isAtUnlock = location == kUnlockRoute;

  if (status == VaultStatus.locked) return isAtUnlock ? null : kUnlockRoute;
  if (isAtUnlock && status == null) return null;
  if (isAtUnlock) return '/terminal';
  return null;
}

/// Notifier that triggers GoRouter redirect re-evaluation
/// whenever the vault state changes.
class _VaultRouterNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final vaultRouterNotifier = _VaultRouterNotifier();

  ref.listen(vaultProvider, (_, _) {
    vaultRouterNotifier.notify();
  });
  ref.onDispose(vaultRouterNotifier.dispose);

  return GoRouter(
    initialLocation: '/terminal',
    refreshListenable: vaultRouterNotifier,
    // Gate the whole app behind the unlock screen while the vault is locked.
    // Without this the master password would never be asked for.
    redirect: (context, state) => resolveVaultRedirect(
      ref.read(vaultProvider).value?.status,
      state.matchedLocation,
    ),
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/terminal'),
      GoRoute(
        path: kUnlockRoute,
        builder: (context, state) => const VaultUnlockDialog(),
      ),
      // File transfer is no longer a rail module: it is always opened for one
      // specific session (`tab`), pushed over the shell so the user returns to
      // wherever they launched it from.
      GoRoute(
        path: '/sftp',
        builder: (context, state) => SftpDualPaneScreen(
          sessionTabId: state.uri.queryParameters['tab'],
          hostLabel: state.uri.queryParameters['label'],
        ),
      ),
      GoRoute(
        path: '/device-link/scan',
        builder: (context, state) => const DeviceLinkPairingFlowScreen(),
      ),
      GoRoute(
        path: '/device-link/pair',
        builder: (context, state) {
          final payload = state.extra;
          if (payload is! DeviceLinkQrPayload) {
            return const Scaffold(
              body: Center(child: Text('Device Link pairing data is missing.')),
            );
          }
          return DeviceLinkPairingQrScreen(
            payload: payload,
            pairingEvents: ref
                .read(terminalTabsProvider.notifier)
                .deviceLinkPairingEvents,
            onCancel: () => context.pop(),
            onPaired: () => context.pop(),
          );
        },
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
          // Index 5: Workspaces
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/workspaces',
                builder: (context, state) => const WorkspaceManagerScreen(),
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
