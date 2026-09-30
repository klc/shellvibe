import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../features/vault/presentation/notifiers/vault_notifier.dart';
import '../router/app_router.dart';
import 'window_chrome.dart';

/// The root navigator's context, which is what the router is reachable from.
///
/// Hosts that sit in `ShadApp.router`'s `builder` wrap the Navigator rather
/// than live under it, so neither `Navigator.of` nor `GoRouter.of` finds
/// anything from their own context.
BuildContext? get hostNavigatorContext {
  final context = rootNavigatorKey.currentContext;
  return context != null && context.mounted ? context : null;
}

/// Goes to [location] on the app's router, if there is one to go through.
void goToHostRoute(String location) {
  final context = hostNavigatorContext;
  if (context != null) GoRouter.maybeOf(context)?.go(location);
}

/// The path the router is showing, or null when there is no router (a test
/// harness) or it has not settled on one.
String? get currentHostRoute {
  final context = hostNavigatorContext;
  if (context == null) return null;
  return GoRouter.maybeOf(context)?.routeInformationProvider.value.uri.path;
}

/// Brings the window forward on [tabId]'s terminal. The one path the tray menu
/// and a notification click both take, so they cannot disagree about it.
Future<void> focusTerminalTab(WidgetRef ref, String tabId) async {
  await showHostWindow();
  ref.read(terminalTabsProvider.notifier).setActiveTab(tabId);
  goToHostRoute('/terminal');
}

/// Whether the vault is locked, locking, or not yet known to be unlocked.
///
/// Fails closed: an unlock attempt puts the provider in loading, and an error
/// leaves it with no value, and neither is a state to show host names or open
/// sessions in. An unconfigured vault has nothing to lock.
bool isVaultLockedOrUnknown(WidgetRef ref) {
  final vault = ref.read(vaultProvider).value;
  return vault == null || vault.status == VaultStatus.locked || vault.isLocking;
}
