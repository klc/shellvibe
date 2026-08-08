import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/utils/platform_capabilities.dart';
import '../features/settings/domain/models/app_settings_model.dart';
import '../features/settings/presentation/notifiers/settings_notifier.dart';
import '../features/device_link/presentation/notifiers/device_link_notifier.dart';
import '../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../features/vault/presentation/notifiers/vault_notifier.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// Root application widget.
///
/// Converts to [ConsumerStatefulWidget] to install an [AppLifecycleListener]
/// that auto-locks the vault when the app moves to the background.
class TerlyApp extends ConsumerStatefulWidget {
  const TerlyApp({super.key});

  @override
  ConsumerState<TerlyApp> createState() => _TerlyAppState();
}

class _TerlyAppState extends ConsumerState<TerlyApp> {
  late final AppLifecycleListener _lifecycleListener;
  Timer? _autoLockTimer;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _onLifecycleChange,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeOpenLaunchShell(ref.read(vaultProvider));
    });
  }

  /// Whether the launch shell has already been opened, so it happens once per
  /// app run rather than on every vault state change.
  bool _launchShellOpened = false;

  /// The app launches straight into the terminal screen (see the router's
  /// initialLocation). On desktop, open a local shell there right away;
  /// flutter_pty cannot run on mobile (iOS sandbox / no local shell on
  /// Android), so mobile starts on the terminal's empty state and connects via
  /// SSH instead.
  ///
  /// Gated on the vault not being locked: while the unlock screen is up the
  /// app is not usable, and spawning the user's login shell behind it would
  /// hand a process (and its full filesystem reach) to someone who has not
  /// passed the lock. The unlock itself calls back in here.
  ///
  /// The gate waits for the vault status to resolve — at first frame it is
  /// still loading, and treating "not locked yet" as "not locked" is exactly
  /// the case being guarded against. A vault that fails to load is not a lock
  /// (the router lets the app through too), so the shell opens.
  void _maybeOpenLaunchShell(AsyncValue<VaultState> vault) {
    if (_launchShellOpened) return;
    if (vault.isLoading && !vault.hasValue) return;
    if (vault.value?.status == VaultStatus.locked) return;
    unawaited(ref.read(deviceLinkProvider.notifier).reconnectStoredProfiles());
    if (!supportsLocalShell) {
      _launchShellOpened = true;
      return;
    }
    _launchShellOpened = true;
    ref.read(terminalTabsProvider.notifier).openLocalTab();
  }

  /// Locks the vault after the configured auto-lock delay when the app enters
  /// a background or hidden state. Honors `autoLockTimerSeconds` (0 = disabled)
  /// instead of locking instantly and unconditionally.
  void _onLifecycleChange(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      final settings = ref.read(settingsProvider).value;
      final delaySeconds = settings?.autoLockTimerSeconds ?? 0;
      if (delaySeconds <= 0) return;
      _autoLockTimer?.cancel();
      _autoLockTimer = Timer(Duration(seconds: delaySeconds), () {
        ref.read(vaultProvider.notifier).lock();
      });
    } else if (state == AppLifecycleState.resumed) {
      _autoLockTimer?.cancel();
      _autoLockTimer = null;
      // iOS tears the UDP socket down while the app is suspended, so a Mosh
      // session needs a rebind on the way back in even when the network never
      // changed. Harmless for every other tab: it only touches live Mosh ones.
      ref.read(terminalTabsProvider.notifier).rehomeMoshSessions();
      unawaited(
        ref.read(deviceLinkProvider.notifier).reconnectStoredProfiles(),
      );
    }
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Unlocking later in the run is what opens the launch shell when the app
    // started on the unlock screen.
    ref.listen(vaultProvider, (_, next) => _maybeOpenLaunchShell(next));

    final router = ref.watch(appRouterProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.value ?? const AppSettingsModel();

    return ShadApp.router(
      title: 'Terly',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildShadTheme(
        settings.copyWith(themeMode: ThemeMode.light),
      ),
      darkTheme: AppTheme.buildShadTheme(
        settings.copyWith(themeMode: ThemeMode.dark),
      ),
      themeMode: settings.themeMode,
      materialThemeBuilder: (context, theme) => AppTheme.buildTheme(settings),
      routerConfig: router,
    );
  }
}
