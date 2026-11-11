import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'foreground_service/foreground_service_host.dart';
import 'notifications/desktop_notification_host.dart';
import 'quick_actions/quick_actions_host.dart';
import 'router/app_router.dart';
import 'theme/app_palette_definitions.dart';
import 'theme/app_theme.dart';
import 'widgets/window_caption_strip.dart';
import 'window/desktop_tray.dart';
import 'window/quit_guard.dart';
import 'window/window_chrome.dart';

/// Overrides the wall clock an auto-lock absence is measured against, so a
/// test can stage a suspension the timer never saw.
@visibleForTesting
DateTime Function()? debugAutoLockClockOverride;

DateTime _wallClockNow() => (debugAutoLockClockOverride ?? DateTime.now)();

/// Root application widget.
///
/// Stateful so it can observe the app lifecycle and auto-lock the vault after
/// it has been in the background too long.
class ShellVibeApp extends ConsumerStatefulWidget {
  const ShellVibeApp({super.key});

  @override
  ConsumerState<ShellVibeApp> createState() => _ShellVibeAppState();
}

class _ShellVibeAppState extends ConsumerState<ShellVibeApp>
    with WidgetsBindingObserver {
  Timer? _autoLockTimer;

  /// Wall-clock time the app went to the background, or null while it is in
  /// the foreground.
  DateTime? _backgroundedAt;

  /// Auto-lock delay in force for the current absence, read when it began.
  Duration _autoLockDelay = Duration.zero;

  /// Desktop only: the last pointer or key event the app saw, and the timer
  /// that locks once none has arrived for the auto-lock delay. A desktop
  /// window can sit in plain view while its user walks away or the OS session
  /// is locked, and is never hidden or paused for it.
  DateTime _lastInputAt = _wallClockNow();
  Timer? _idleTimer;

  /// Android: whether the window was last asked to be kept out of
  /// screenshots, screen recordings and the recent-apps thumbnail.
  bool? _secureWindow;

  static const _secureWindowChannel = MethodChannel(
    'dev.shellvibe.app/secure_window',
  );

  /// Last canvas and brightness handed to the window frame, so a rebuild that
  /// did not change the theme does not cross the method channel again.
  (Color, Brightness)? _appliedChrome;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!isMobilePlatform) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointerInput);
      HardwareKeyboard.instance.addHandler(_onKeyInput);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeOpenLaunchShell(ref.read(vaultProvider));
      _syncSecureWindow(ref.read(vaultProvider));
      _syncWindowChrome();
      _offerUnreportedCrash(ref.read(vaultProvider));
    });
  }

  bool _crashOffered = false;

  /// A crash from the last run, offered once as a GitHub issue the user files
  /// themselves. On the root navigator: this widget sits above the router and
  /// has no navigator of its own.
  ///
  /// Not over the unlock screen: the report quotes the log, which can name
  /// hosts, to whoever is at the machine. Offered once the vault opens.
  void _offerUnreportedCrash(AsyncValue<VaultState> vault) {
    if (_crashOffered) return;
    if (!vault.hasValue || vault.value!.status == VaultStatus.locked) return;
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    _crashOffered = true;
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
  /// flutter_pty2 cannot run on mobile (iOS sandbox / no local shell on
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
  /// the case being guarded against. A vault that fails to *load* might be
  /// locked too, so it fails closed the same way: the router shows the error
  /// and a retry, and the shell opens once a retry reads the vault.
  void _maybeOpenLaunchShell(AsyncValue<VaultState> vault) {
    if (!vault.hasValue) return;
    if (vault.value!.status == VaultStatus.locked) return;
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

  /// Android only: FLAG_SECURE while a master password guards the vault. The
  /// auto-lock lands on the way back in, so without it the recent-apps
  /// thumbnail goes on showing an unlocked session after the lock is due. A
  /// vault not read yet counts as guarded. iOS covers its snapshot natively
  /// (SceneDelegate).
  void _syncSecureWindow(AsyncValue<VaultState> vault) {
    if (runtimeTargetPlatform != TargetPlatform.android) return;
    final secure = vault.value?.status != VaultStatus.unconfigured;
    if (secure == _secureWindow) return;
    _secureWindow = secure;
    unawaited(
      _secureWindowChannel.invokeMethod<void>('setSecure', secure).catchError((
        Object error,
      ) {
        debugPrint('[SecureWindow] $error');
      }),
    );
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
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
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

  Duration get _autoLockSetting => Duration(
    seconds: ref.read(settingsProvider).value?.autoLockTimerSeconds ?? 0,
  );

  void _onPointerInput(PointerEvent event) => _onInput();

  bool _onKeyInput(KeyEvent event) {
    _onInput();
    return false; // Observed only; the key goes on to whoever has focus.
  }

  void _onInput() {
    final now = _wallClockNow();
    final idle = now.difference(_lastInputAt);
    _lastInputAt = now;
    // The idle timer counts on the monotonic clock, which stops while the
    // machine sleeps. The first input after a gap it did not see locks before
    // it reaches anything behind the lock.
    final delay = _autoLockSetting;
    if (delay > Duration.zero && (idle.isNegative || idle >= delay)) {
      _lockIfUnlocked();
    }
    if (_idleTimer == null) _checkIdle();
  }

  /// Locks once the app has seen no input for the auto-lock delay, else
  /// checks again when it would be due. Re-armed by the next input after a
  /// lock or while auto-lock is off, so an idle app runs no timer at all.
  void _checkIdle() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (isMobilePlatform) return;
    final delay = _autoLockSetting;
    if (delay <= Duration.zero) return;
    final idle = _wallClockNow().difference(_lastInputAt);
    if (idle.isNegative || idle >= delay) {
      _lockIfUnlocked();
      return;
    }
    _idleTimer = Timer(delay - idle, _checkIdle);
  }

  void _lockIfUnlocked() {
    if (ref.read(vaultProvider).value?.status != VaultStatus.unlocked) return;
    unawaited(ref.read(vaultProvider.notifier).lock());
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

  /// macOS: ⌘Q, the app menu, the Dock and the tray's Quit all end here.
  /// Windows and Linux quit through the tray host, which asks the same way.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!isMobilePlatform && !await confirmQuit(ref)) {
      return AppExitResponse.cancel;
    }
    // The auto-clear timer dies with the process; a copied secret must not.
    await ref.read(clipboardAutoClearServiceProvider).clearNow();
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    _idleTimer?.cancel();
    if (!isMobilePlatform) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointerInput);
      HardwareKeyboard.instance.removeHandler(_onKeyInput);
    }
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
    //
    // The MCP server cannot start behind a locked vault either, so a launch
    // that begins locked has to try again once it opens.
    ref.listen(vaultProvider, (_, next) {
      _maybeOpenLaunchShell(next);
      _offerUnreportedCrash(next);
      _syncSecureWindow(next);
      unawaited(
        ref.read(mcpSettingsProvider.notifier).ensureServerMatchesSetting(),
      );
    });
    ref.listen(settingsProvider, (_, _) {
      _syncWindowChrome();
      // A changed delay applies from now, not from the next input.
      _checkIdle();
    });

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
            ? QuickActionsHost(child: _withForegroundService(host))
            : WindowResizeEdges(
                child: DesktopTrayHost(
                  child: DesktopNotificationHost(child: host),
                ),
              );
      },
    );
  }
}

/// Keeps sessions and tunnels running behind the app on Android, the one
/// mobile platform with a foreground service to do it with.
Widget _withForegroundService(Widget child) =>
    supportsForegroundService ? ForegroundServiceHost(child: child) : child;
