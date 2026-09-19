import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/utils/platform_capabilities.dart';
import '../features/device_link/presentation/notifiers/device_link_notifier.dart';
import '../features/mcp/presentation/notifiers/mcp_settings_notifier.dart';
import '../features/mcp/presentation/widgets/mcp_approval_host.dart';
import '../features/settings/domain/models/app_settings_model.dart';
import '../features/settings/presentation/notifiers/settings_notifier.dart';
import '../features/cloud_backup/presentation/notifiers/sync_notifier.dart';
import '../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../features/vault/presentation/notifiers/vault_notifier.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'window/window_chrome.dart';

/// Root application widget.
///
/// Converts to [ConsumerStatefulWidget] to install an [AppLifecycleListener]
/// that auto-locks the vault when the app moves to the background.
class ShellVibeApp extends ConsumerStatefulWidget {
  const ShellVibeApp({super.key});

  @override
  ConsumerState<ShellVibeApp> createState() => _ShellVibeAppState();
}

class _ShellVibeAppState extends ConsumerState<ShellVibeApp>
    with WidgetsBindingObserver {
  late final AppLifecycleListener _lifecycleListener;
  Timer? _autoLockTimer;

  /// Last brightness handed to the window frame, so a rebuild that did not
  /// change the theme does not cross the method channel again.
  Brightness? _appliedChromeBrightness;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _onLifecycleChange,
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeOpenLaunchShell(ref.read(vaultProvider));
      _syncWindowChrome();
    });
  }

  /// [ThemeMode.system] resolves against the platform, so the frame has to
  /// follow the OS flipping too — not only the setting changing.
  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    _syncWindowChrome();
  }

  void _syncWindowChrome() {
    final mode =
        ref.read(settingsProvider).value?.themeMode ?? ThemeMode.system;
    final brightness = switch (mode) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    if (brightness == _appliedChromeBrightness) return;
    _appliedChromeBrightness = brightness;
    unawaited(syncWindowChromeToTheme(brightness));
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
  /// the case being guarded against. A vault that fails to *load* is not a
  /// lock (the router lets the app through too), so the shell opens.
  ///
  /// Device Link is gated more tightly than the shell: an unresolved or failed
  /// vault opens no LAN listener, but it must still leave the user with a
  /// usable local terminal.
  void _maybeOpenLaunchShell(AsyncValue<VaultState> vault) {
    // A failed vault read keeps `isLoading` set while Riverpod retries it, so
    // "still loading" has to mean no value *and* no error — otherwise a vault
    // that cannot be read at all would hold the shell back forever.
    if (vault.isLoading && !vault.hasValue && !vault.hasError) return;
    if (vault.value?.status == VaultStatus.locked) return;
    if (!_launchShellOpened) {
      _launchShellOpened = true;
      if (supportsLocalShell) {
        ref.read(terminalTabsProvider.notifier).openLocalTab();
      }
    }
    if (_vaultAllowsDeviceLink(vault)) {
      _reconnectDeviceLinkIfVaultUnlocked();
      if (supportsLocalShell) unawaited(_ensureDeviceLinkServerSafely());
    }
  }

  bool _vaultAllowsDeviceLink(AsyncValue<VaultState> vault) {
    return vault.hasValue &&
        !vault.isLoading &&
        !vault.hasError &&
        vault.value!.allowsDeviceLink;
  }

  Future<void> _ensureDeviceLinkServerSafely() async {
    if (!supportsLocalShell || !_launchShellOpened) return;
    final terminalNotifier = ref.read(terminalTabsProvider.notifier);
    final vault = ref.read(vaultProvider);
    if (!_vaultAllowsDeviceLink(vault)) {
      await terminalNotifier.stopDeviceLinkServer();
      return;
    }
    try {
      await terminalNotifier.ensureDeviceLinkServerForPairedDevices();
    } on Object catch (error, stackTrace) {
      debugPrint('[Device Link] startup listener unavailable: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _reconnectDeviceLinkIfVaultUnlocked() {
    final vault = ref.read(vaultProvider);
    if (!_vaultAllowsDeviceLink(vault)) return;
    unawaited(ref.read(deviceLinkProvider.notifier).reconnectStoredProfiles());
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
      _reconnectDeviceLinkIfVaultUnlocked();
      unawaited(_ensureDeviceLinkServerSafely());
      // Coming back to the app is the moment the user is most likely to be
      // looking at data another device changed while this one was away.
      unawaited(ref.read(syncProvider.notifier).syncNow());
    }
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    _lifecycleListener.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Unlocking later in the run is what opens the launch shell when the app
    // started on the unlock screen. Tearing the Device Link listener down on
    // an unavailable vault belongs to TerminalTabsNotifier, which owns the
    // server and watches the same provider; duplicating it here would race
    // against its own start/stop sequencing.
    ref.listen(vaultProvider, (_, next) => _maybeOpenLaunchShell(next));
    ref.listen(settingsProvider, (_, _) => _syncWindowChrome());

    // Watched, not read: this is what builds the MCP settings at boot, which
    // is where the persisted master switch gets reconciled against what is
    // actually running. Without a watcher here the reconciliation only
    // happens the first time someone opens the AI Access screen — so an app
    // relaunched with the switch on would sit there not serving, and the
    // agent's bridge would report the app as not running.
    ref.watch(mcpSettingsProvider);

    // Same reasoning, for automatic sync: watched here so it runs for the
    // whole app run rather than only while the settings screen that shows its
    // status happens to be open. It is also what attaches the journal that
    // records local changes, which has to happen whether or not sync itself
    // is switched on.
    ref.watch(syncProvider);
    // The server cannot start behind a locked vault, so a launch that begins
    // locked has to try again once it opens.
    ref.listen(vaultProvider, (_, _) {
      unawaited(
        ref.read(mcpSettingsProvider.notifier).ensureServerMatchesSetting(),
      );
    });

    final router = ref.watch(appRouterProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.value ?? const AppSettingsModel();

    return ShadApp.router(
      title: 'ShellVibe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildShadTheme(settings, brightness: Brightness.light),
      darkTheme: AppTheme.buildShadTheme(settings, brightness: Brightness.dark),
      themeMode: settings.themeMode,
      materialThemeBuilder: (context, theme) =>
          AppTheme.buildTheme(settings, brightness: theme.brightness),
      routerConfig: router,
      // The MCP approval prompts are mounted above every route rather than
      // inside one: an agent can ask for access while the user is on any
      // screen, and an approval window that depends on where the user
      // happened to navigate would silently time out into a refusal.
      builder: (context, child) =>
          McpApprovalHost(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Backwards compatibility alias
