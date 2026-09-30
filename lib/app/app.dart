import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/utils/platform_capabilities.dart';
import '../features/device_link/presentation/notifiers/device_link_notifier.dart';
import '../features/mcp/presentation/notifiers/mcp_settings_notifier.dart';
import '../features/mcp/presentation/widgets/mcp_approval_host.dart';
import '../features/settings/domain/models/app_settings_model.dart';
import '../features/settings/presentation/dialogs/problem_report_dialog.dart';
import '../features/settings/presentation/notifiers/settings_notifier.dart';
import '../features/cloud_backup/presentation/notifiers/cloud_backup_notifier.dart';
import '../features/cloud_backup/presentation/notifiers/sync_notifier.dart';
import '../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../features/vault/presentation/notifiers/vault_notifier.dart';
import 'quick_actions/quick_actions_host.dart';
import 'router/app_router.dart';
import 'theme/app_palette_definitions.dart';
import 'theme/app_theme.dart';
import 'window/desktop_tray.dart';
import 'window/window_chrome.dart';

/// Overrides the wall clock an auto-lock absence is measured against, so a
/// test can stage a suspension the timer never saw.
@visibleForTesting
DateTime Function()? debugAutoLockClockOverride;

DateTime _wallClockNow() => (debugAutoLockClockOverride ?? DateTime.now)();

/// Root application widget.
///
/// Converts to [ConsumerStatefulWidget] to install an [AppLifecycleListener]
/// that auto-locks the vault after it has been in the background too long.
class ShellVibeApp extends ConsumerStatefulWidget {
  const ShellVibeApp({super.key});

  @override
  ConsumerState<ShellVibeApp> createState() => _ShellVibeAppState();
}

class _ShellVibeAppState extends ConsumerState<ShellVibeApp>
    with WidgetsBindingObserver {
  late final AppLifecycleListener _lifecycleListener;
  Timer? _autoLockTimer;

  /// Wall-clock time the app went to the background, or null while it is in
  /// the foreground.
  DateTime? _backgroundedAt;

  /// Auto-lock delay in force for the current absence, read when it began.
  Duration _autoLockDelay = Duration.zero;

  /// Last canvas and brightness handed to the window frame, so a rebuild that
  /// did not change the theme does not cross the method channel again.
  (Color, Brightness)? _appliedChrome;

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
      _offerUnreportedCrash();
    });
  }

  /// A crash from the last run, offered once as a GitHub issue the user files
  /// themselves. On the root navigator: this widget sits above the router and
  /// has no navigator of its own.
  void _offerUnreportedCrash() {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    unawaited(
      offerUnreportedCrash(context).catchError((Object error) {
        debugPrint('[CrashLog] could not offer the last crash: $error');
      }),
    );
  }

  /// [ThemeMode.system] resolves against the platform, so the frame has to
  /// follow the OS flipping too — not only the setting changing.
  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    _syncWindowChrome();
  }

  /// Tints the frame with the selected palette's canvas, so a palette switch
  /// at the same brightness re-tints it too. Falls back to the same defaults
  /// [build] draws with while the settings are still loading.
  void _syncWindowChrome() {
    final settings =
        ref.read(settingsProvider).value ?? const AppSettingsModel();
    final brightness = switch (settings.themeMode) {
      ThemeMode.dark => Brightness.dark,
      ThemeMode.light => Brightness.light,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    final palette = AppPaletteDefinition.forPalette(settings.palette);
    final canvas = brightness == Brightness.dark
        ? palette.darkTokens.canvas
        : palette.lightTokens.canvas;
    if (_appliedChrome == (canvas, brightness)) return;
    _appliedChrome = (canvas, brightness);
    unawaited(syncWindowChromeToTheme(canvas: canvas, brightness: brightness));
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

  /// Tracks the app leaving and returning to the foreground.
  ///
  /// Only hidden and paused count as leaving. A desktop window going inactive
  /// is a focus change, not an absence: it flips between inactive and resumed
  /// on every alt-tab, and treating that as a return would run a sync round
  /// trip and rebind every Mosh socket each time. The return is handled at
  /// the first state past hidden (inactive on the way to resumed), which is
  /// the earliest point the vault can be locked before it is looked at.
  void _onLifecycleChange(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _onBackgrounded();
      case AppLifecycleState.inactive:
      case AppLifecycleState.resumed:
        _onReturned();
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Starts the auto-lock clock. Honors `autoLockTimerSeconds` (0 = disabled)
  /// instead of locking instantly and unconditionally.
  void _onBackgrounded() {
    // hidden is followed by paused on the way out; the absence began at the
    // first of them.
    if (_backgroundedAt != null) return;
    _backgroundedAt = _wallClockNow();
    final settings = ref.read(settingsProvider).value;
    _autoLockDelay = Duration(seconds: settings?.autoLockTimerSeconds ?? 0);
    if (_autoLockDelay <= Duration.zero) return;
    // Locks on time while the process keeps running in the background, which
    // a desktop does. A suspended phone runs no timers at all, and while it
    // sleeps the monotonic clock a Timer counts on stops too, so this alone
    // would let the vault open unlocked hours later; [_onReturned] checks the
    // wall clock for that case.
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer(_autoLockDelay, () {
      unawaited(ref.read(vaultProvider.notifier).lock());
    });
  }

  void _onReturned() {
    final backgroundedAt = _backgroundedAt;
    if (backgroundedAt == null) return;
    _backgroundedAt = null;
    _autoLockTimer?.cancel();
    _autoLockTimer = null;

    if (_autoLockDelay > Duration.zero) {
      final away = _wallClockNow().difference(backgroundedAt);
      // A clock set backwards while away reads as a negative absence. That is
      // no proof the delay has not passed, so it locks too.
      if (away.isNegative || away >= _autoLockDelay) {
        // Flips the vault to locked synchronously, so the Device Link calls
        // below already see it closed.
        unawaited(ref.read(vaultProvider.notifier).lock());
      }
    }

    // iOS tears the UDP socket down while the app is suspended, so a Mosh
    // session needs a rebind on the way back in even when the network never
    // changed. Harmless for every other tab: it only touches live Mosh ones.
    ref.read(terminalTabsProvider.notifier).rehomeMoshSessions();
    _reconnectDeviceLinkIfVaultUnlocked();
    unawaited(_ensureDeviceLinkServerSafely());
    // Coming back to the app is the moment the user is most likely to be
    // looking at data another device changed while this one was away.
    unawaited(ref.read(syncProvider.notifier).syncNow());
    // And the only other moment a scheduled backup can run. There is no
    // background task, so a device that sat closed past its interval is due
    // the moment someone opens it again.
    unawaited(ref.read(cloudBackupProvider.notifier).maybeBackUpOnSchedule());
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

    // And cloud backup, for the same reason again. It holds the passphrase,
    // the head and the schedule a backup runs on, none of which should wait
    // for someone to open the settings screen -- an automatic backup that
    // only happens while its own settings page is visible is not automatic.
    ref.watch(cloudBackupProvider);

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
      //
      // The tray lives here too: it outlasts every route, and on a desktop it
      // is what keeps the app running once the window is gone. A phone has no
      // tray; its counterpart is the app-icon shortcut menu.
      builder: (context, child) {
        final host = McpApprovalHost(child: child ?? const SizedBox.shrink());
        return isMobilePlatform
            ? QuickActionsHost(child: host)
            : DesktopTrayHost(child: host);
      },
    );
  }
}

/// Backwards compatibility alias
