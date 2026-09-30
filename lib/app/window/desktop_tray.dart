import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/network/ssh_session_manager.dart';
import '../../core/network/tunnel_engine.dart';
import '../../features/bookmarks/presentation/notifiers/bookmarks_notifier.dart';
import '../../features/hosts/domain/models/host_model.dart';
import '../../features/hosts/domain/services/host_launcher.dart';
import '../../features/hosts/presentation/notifiers/hosts_notifier.dart';
import '../../features/settings/domain/models/app_settings_model.dart';
import '../../features/settings/presentation/notifiers/settings_notifier.dart';
import '../../features/templates/domain/models/template_model.dart';
import '../../features/templates/presentation/notifiers/templates_notifier.dart';
import '../../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../features/tunnels/presentation/providers/tunnels_providers.dart';
import '../../features/vault/domain/models/identity_model.dart';
import '../../features/vault/presentation/notifiers/vault_notifier.dart';
import '../router/app_router.dart';
import 'desktop_tray_menu.dart';
import 'window_chrome.dart';

/// Overrides whether the window close is intercepted, so tests cover the
/// Windows and Linux path on any host.
@visibleForTesting
bool? debugTrayInterceptsCloseOverride;

/// Puts ShellVibe in the system tray (the menu bar on macOS) and, where the
/// platform would otherwise quit, turns closing the window into hiding it.
///
/// A tunnel or a session outlives the window it was opened from only if the
/// process does. On Windows and Linux the last window closing ends the
/// process, so with [AppSettingsModel.keepRunningInTray] on the close is
/// intercepted and the window hidden instead, and Quit moves to the tray menu.
/// macOS already keeps the app alive with no window (see `AppDelegate`), so
/// there the icon is only a status line and a way back to the window.
///
/// The menu is how what is still running behind a hidden window is seen and
/// handled without opening it: sessions can be brought forward, tunnels
/// stopped or started, and a favorite host or a template opened. See
/// [buildTrayMenu] for the layout.
class DesktopTrayHost extends ConsumerStatefulWidget {
  const DesktopTrayHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DesktopTrayHost> createState() => _DesktopTrayHostState();
}

class _DesktopTrayHostState extends ConsumerState<DesktopTrayHost>
    with TrayListener, WindowListener {
  /// Whether the icon is currently up. Tracked here rather than asked of the
  /// plugin, which has no way to say.
  bool _trayShown = false;

  /// Serialises tray updates: a settings change and a count change arriving
  /// together must not interleave `setIcon` with `destroy`.
  Future<void> _pending = Future.value();

  /// What the menu on screen was built from. A provider that changes without
  /// changing this (a tunnel's transfer speed, every second) costs no menu
  /// rebuild.
  TrayMenuData? _lastMenuData;

  /// Rules a start is already in flight for, so a second click while an SSH
  /// connection is being dialed does not start the forward twice.
  final Set<String> _startingRuleIds = {};

  bool get _interceptsClose =>
      debugTrayInterceptsCloseOverride ??
      (Platform.isWindows || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  bool get _enabled =>
      (ref.read(settingsProvider).value ?? const AppSettingsModel())
          .keepRunningInTray;

  void _sync() {
    _pending = _pending.then((_) => _apply()).catchError((Object e) {
      debugPrint('[DesktopTray] $e');
    });
  }

  /// Refreshes the menu if the change that just arrived is one it shows.
  void _syncMenu() {
    if (!_trayShown) return;
    if (_readMenuData() == _lastMenuData) return;
    _sync();
  }

  Future<void> _apply() async {
    if (!mounted) return;
    final enabled = _enabled;

    if (!enabled) {
      // Let the close through before the icon goes: in between, a close that
      // is still intercepted would hide the window with no icon to bring it
      // back through.
      if (_interceptsClose) await windowManager.setPreventClose(false);
      if (_trayShown) {
        await trayManager.destroy();
        _trayShown = false;
        _lastMenuData = null;
      }
      return;
    }

    if (!_trayShown) {
      try {
        if (Platform.isMacOS) {
          await trayManager.setIcon(
            'assets/brand/tray_macos.png',
            isTemplate: true,
          );
        } else {
          await trayManager.setIcon(
            Platform.isWindows
                ? 'assets/brand/tray.ico'
                : 'assets/brand/tray.png',
          );
        }
        if (!Platform.isLinux) await trayManager.setToolTip('ShellVibe');
      } catch (_) {
        // A desktop without a tray host (a bare Linux window manager) still
        // runs the app, but has no icon to hide behind, so closing the window
        // has to go on quitting it.
        if (_interceptsClose) await windowManager.setPreventClose(false);
        rethrow;
      }
      _trayShown = true;
    }
    // Only once the icon is up: intercepting the close earlier hides the
    // window with nothing on screen to show it again.
    if (_interceptsClose) await windowManager.setPreventClose(true);
    // Recorded before the await: a change that lands while the plugin is busy
    // must compare against what is being shown, not what was shown before.
    final data = _readMenuData();
    _lastMenuData = data;
    await trayManager.setContextMenu(buildTrayMenu(data));
  }

  /// Whether the vault is locked, locking, or not yet known to be unlocked.
  ///
  /// Fails closed: an unlock attempt puts the provider in loading, and an
  /// error leaves it with no value, and neither is a state to show host names
  /// or open sessions in. An unconfigured vault has nothing to lock.
  bool get _vaultLocked {
    final vault = ref.read(vaultProvider).value;
    return vault == null ||
        vault.status == VaultStatus.locked ||
        vault.isLocking;
  }

  TrayMenuData _readMenuData() {
    final hosts = ref.read(hostsProvider).value ?? const <HostModel>[];
    final templates =
        ref.read(templatesProvider).value ?? const <TemplateModel>[];
    final bookmarks = ref.read(bookmarksProvider).value ?? const [];
    final hostLabels = {for (final host in hosts) host.id: host.label};

    if (_vaultLocked) {
      return TrayMenuData(
        locked: true,
        sessionCount: ref
            .read(terminalTabsProvider)
            .tabs
            .where((tab) => tab.splitParentId == null)
            .length,
        activeTunnelCount:
            (ref.read(activeTunnelsStreamProvider).value ??
                    const <ActiveTunnel>[])
                .where((tunnel) => tunnel.isActive)
                .length,
      );
    }

    String tunnelLabel(String hostId, String route) {
      final host = hostLabels[hostId];
      return host == null ? route : '$host · $route';
    }

    final active = [
      for (final tunnel
          in ref.read(activeTunnelsStreamProvider).value ??
              const <ActiveTunnel>[])
        if (tunnel.isActive) tunnel,
    ];
    final activeIds = {for (final tunnel in active) tunnel.ruleId};

    TrayTarget hostTarget(HostModel host) =>
        TrayTarget(id: host.id, label: host.label);
    TrayTarget templateTarget(TemplateModel template) =>
        TrayTarget(id: template.id, label: template.name);

    return TrayMenuData(
      sessions: [
        for (final tab in ref.read(terminalTabsProvider).tabs)
          if (tab.splitParentId == null)
            TraySession(
              tabId: tab.id,
              title: tab.title,
              state: tab.isConnected
                  ? TraySessionState.connected
                  : tab.isConnecting
                  ? TraySessionState.connecting
                  : TraySessionState.disconnected,
            ),
      ],
      activeTunnels: [
        for (final tunnel in active)
          TrayTunnel(
            ruleId: tunnel.ruleId,
            label: tunnelLabel(
              tunnel.hostId,
              tunnelRouteLabel(
                type: tunnel.type,
                localPort: tunnel.localPort,
                remoteHost: tunnel.remoteHost,
                remotePort: tunnel.remotePort,
              ),
            ),
          ),
      ],
      idleTunnels: [
        for (final rule in ref.read(tunnelsProvider).rules)
          if (!activeIds.contains(rule.id))
            TrayTunnel(
              ruleId: rule.id,
              label: tunnelLabel(
                rule.hostId,
                tunnelRouteLabel(
                  type: rule.type,
                  localPort: rule.localPort,
                  remoteHost: rule.remoteHost,
                  remotePort: rule.remotePort,
                ),
              ),
            ),
      ],
      // Bookmark order, not list order: a favorites bar is arranged by whoever
      // starred the entries. Same derivation as the command palette.
      favoriteHosts: [
        for (final bookmark in bookmarks)
          if (bookmark.hostId != null)
            for (final host in hosts)
              if (host.id == bookmark.hostId) hostTarget(host),
      ],
      favoriteTemplates: [
        for (final bookmark in bookmarks)
          if (bookmark.templateId != null)
            for (final template in templates)
              if (template.id == bookmark.templateId) templateTarget(template),
      ],
      templates: [for (final template in templates) templateTarget(template)],
    );
  }

  Future<void> _quit() async {
    try {
      await trayManager.destroy();
      _trayShown = false;
      if (_interceptsClose) {
        await windowManager.setPreventClose(false);
        // The runner ends the process with its last window.
        await windowManager.destroy();
      } else {
        // macOS keeps running with no window; this is the app-level quit.
        await SystemNavigator.pop();
      }
    } catch (e) {
      debugPrint('[DesktopTray] quit failed, exiting: $e');
      exit(0);
    }
  }

  @override
  void onWindowClose() {
    unawaited(
      _onWindowClose().catchError((Object e) {
        debugPrint('[DesktopTray] close failed: $e');
      }),
    );
  }

  Future<void> _onWindowClose() async {
    // window_manager reports every close, intercepted or not, on every
    // platform. One that was not intercepted is already going through and is
    // not ours to finish: on macOS the app outlives its window (AppDelegate),
    // and elsewhere the runner ends with it. Quitting here would take every
    // session and tunnel down with a window that was only being closed.
    if (!await windowManager.isPreventClose()) return;
    // Intercepted, but the setting may have just been turned off, or the icon
    // may be gone: hiding then would leave no way back.
    if (_enabled && _trayShown) {
      await windowManager.hide();
    } else {
      await _quit();
    }
  }

  @override
  void onTrayIconMouseDown() {
    // A click on a Windows tray icon means "open"; a macOS menu bar item
    // opens its menu. Linux trays show the menu themselves.
    if (Platform.isWindows) {
      unawaited(showHostWindow());
    } else {
      unawaited(trayManager.popUpContextMenu());
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final action = TrayAction.parse(menuItem.key);
    if (action == null) return;
    // The menu on screen may be older than the lock. Anything that would name
    // a host, open a session or dial out only brings the window up, and the
    // router puts the unlock screen in front of it. Stopping a tunnel is let
    // through: it discloses nothing, and ends something the user started.
    if (_vaultLocked &&
        action is! TrayShow &&
        action is! TrayQuit &&
        action is! TrayStopTunnel) {
      unawaited(showHostWindow());
      return;
    }
    switch (action) {
      case TrayShow():
        unawaited(showHostWindow());
      case TrayQuit():
        unawaited(_quit());
      case TrayFocusTab(:final tabId):
        unawaited(_run('focus session', () => _focusTab(tabId)));
      case TrayStopTunnel(:final ruleId):
        unawaited(_run('stop tunnel', () => _stopTunnel(ruleId)));
      case TrayStartTunnel(:final ruleId):
        unawaited(_run('start tunnel', () => _startTunnel(ruleId)));
      case TrayConnectHost(:final hostId):
        unawaited(_run('connect', () => _connectHost(hostId)));
      case TrayRunTemplate(:final templateId):
        unawaited(_run('run template', () => _runTemplate(templateId)));
    }
  }

  /// Runs a menu action whose failure has nowhere to surface but the log: the
  /// click came from the OS, not from a widget that could show a toast.
  Future<void> _run(String what, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('[DesktopTray] $what failed: $e');
    }
  }

  /// The root navigator's context, which is what dialogs, toasts and the
  /// router are reachable from.
  ///
  /// Not this widget's own: it is mounted through `ShadApp.router`'s `builder`,
  /// which wraps the Navigator rather than living under it, so neither
  /// `Navigator.of` nor `GoRouter.of` finds anything from here.
  BuildContext? get _navigatorContext {
    final context = rootNavigatorKey.currentContext;
    return context != null && context.mounted ? context : null;
  }

  HostLauncher? _launcher() {
    final context = _navigatorContext;
    return context == null ? null : HostLauncher(context: context, ref: ref);
  }

  void _toast(ShadToast toast) {
    final context = _navigatorContext;
    if (context != null) ShadToaster.of(context).show(toast);
  }

  void _goToTerminal() {
    final context = _navigatorContext;
    if (context != null) GoRouter.maybeOf(context)?.go('/terminal');
  }

  Future<void> _focusTab(String tabId) async {
    await showHostWindow();
    ref.read(terminalTabsProvider.notifier).setActiveTab(tabId);
    _goToTerminal();
  }

  /// Stops through the notifier, as the Tunnels screen does, so the pooled SSH
  /// connection a forward opened for itself is released with it.
  Future<void> _stopTunnel(String ruleId) =>
      ref.read(tunnelsProvider.notifier).stopRule(ruleId);

  /// Starts a saved forward without bringing the window up: dialing in needs
  /// nothing the user has to see when the host has stored credentials and a
  /// known key. The two prompts that do need a screen show the window first,
  /// so a start from a hidden window asks rather than failing silently.
  Future<void> _startTunnel(String ruleId) async {
    if (!_startingRuleIds.add(ruleId)) return;
    try {
      final rule = ref
          .read(tunnelsProvider)
          .rules
          .where((rule) => rule.id == ruleId)
          .firstOrNull;
      if (rule == null) return;

      Future<({bool ok, IdentityModel? identity})> resolveIdentity(
        HostModel host,
      ) async {
        await showHostWindow();
        final launcher = _launcher();
        if (launcher == null) return (ok: false, identity: null);
        return launcher.resolveIdentity(host);
      }

      Future<bool> promptHostKey(
        String hostname,
        int port,
        String keyType,
        String fingerprint,
        HostKeyVerificationStatus status,
      ) async {
        await showHostWindow();
        final launcher = _launcher();
        if (launcher == null) return false;
        return launcher.promptHostKey(
          hostname,
          port,
          keyType,
          fingerprint,
          status,
        );
      }

      try {
        await ref
            .read(tunnelsProvider.notifier)
            .startRule(
              rule,
              resolveIdentity: resolveIdentity,
              onHostKeyPrompt: promptHostKey,
            );
      } catch (e) {
        // Nothing on screen says it failed, and the menu only shows the rule
        // still stopped, so bring the window up to say why.
        await showHostWindow();
        _toast(
          ShadToast.destructive(
            title: const Text('Tunnel could not start'),
            description: Text('$e'),
          ),
        );
      }
    } finally {
      _startingRuleIds.remove(ruleId);
    }
  }

  Future<void> _connectHost(String hostId) async {
    final host = (ref.read(hostsProvider).value ?? const <HostModel>[])
        .where((host) => host.id == hostId)
        .firstOrNull;
    if (host == null) return;
    await showHostWindow();
    // The launcher, not a connect written out here: a host with no stored
    // identity has to be asked for one and an unknown host key shown.
    await _launcher()?.connect(host);
  }

  /// Replays a saved layout, the same way the command palette does.
  Future<void> _runTemplate(String templateId) async {
    final template =
        (ref.read(templatesProvider).value ?? const <TemplateModel>[])
            .where((template) => template.id == templateId)
            .firstOrNull;
    if (template == null) return;
    await showHostWindow();
    final launcher = _launcher();
    if (launcher == null) return;
    final result = await ref
        .read(templatesProvider.notifier)
        .runTemplate(
          template,
          resolveIdentity: launcher.resolveIdentity,
          onHostKeyPrompt: launcher.promptHostKey,
        );
    _goToTerminal();
    if (!result.isComplete) {
      _toast(
        ShadToast.destructive(
          description: Text('Some panes of "${template.name}" could not open.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      settingsProvider.select((s) => s.value?.keepRunningInTray),
      (_, _) => _sync(),
    );
    // Everything the menu reads is listened to, which also keeps the
    // auto-disposing ones (hosts, tunnel rules) loaded while the window is
    // hidden. [_syncMenu] drops the changes the menu does not show.
    ref.listen(activeTunnelsStreamProvider, (_, _) => _syncMenu());
    // `isConnected` is a mutable field, but the notifier re-emits the tab list
    // whenever one flips, which is what lets a dropped session show up here.
    ref.listen(terminalTabsProvider, (_, _) => _syncMenu());
    ref.listen(tunnelsProvider.select((s) => s.rules), (_, _) => _syncMenu());
    ref.listen(hostsProvider, (_, _) => _syncMenu());
    ref.listen(templatesProvider, (_, _) => _syncMenu());
    ref.listen(bookmarksProvider, (_, _) => _syncMenu());
    // Lock and unlock swap the whole menu.
    ref.listen(vaultProvider, (_, _) => _syncMenu());
    return widget.child;
  }
}
