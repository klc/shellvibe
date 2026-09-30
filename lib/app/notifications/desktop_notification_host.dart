import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/tunnel_engine.dart';
import '../../features/hosts/domain/models/host_model.dart';
import '../../features/hosts/presentation/notifiers/hosts_notifier.dart';
import '../../features/settings/domain/models/app_settings_model.dart';
import '../../features/settings/presentation/notifiers/settings_notifier.dart';
import '../../features/terminal/domain/models/terminal_tab_session.dart';
import '../../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../features/tunnels/presentation/providers/tunnels_providers.dart';
import '../window/desktop_tray_menu.dart' show tunnelRouteLabel;
import '../window/host_navigation.dart';
import '../window/window_chrome.dart';
import 'alert_detectors.dart';
import 'app_alert.dart';
import 'notification_policy.dart';
import 'notification_providers.dart';

/// Turns what happens behind a hidden or unfocused window into OS
/// notifications, and into the tray's error icon.
///
/// It watches three things, none of which the tabs or the tunnel engine report
/// on their own: sessions that drop (see [SessionDropDetector]), forwards that
/// stop with an error ([TunnelFailureDetector]), and each terminal's bell and
/// OSC 9 / OSC 777 notification requests, which xterm3 surfaces as
/// `Terminal.onBell` and `Terminal.onNotification`. Whether any of it reaches
/// the user is [NotificationPolicy]'s call.
///
/// A click on a notification shows the window and, for a session, selects its
/// tab, through the same path the tray menu uses. Click callbacks are the
/// plugin's: macOS and Windows deliver them, and Linux does wherever the
/// notification server supports actions (most do).
class DesktopNotificationHost extends ConsumerStatefulWidget {
  const DesktopNotificationHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DesktopNotificationHost> createState() =>
      _DesktopNotificationHostState();
}

class _DesktopNotificationHostState
    extends ConsumerState<DesktopNotificationHost> {
  final NotificationPolicy _policy = NotificationPolicy();
  final SessionDropDetector _drops = SessionDropDetector();
  final TunnelFailureDetector _tunnelFailures = TunnelFailureDetector();

  /// Tabs whose terminal already reports to [_raise].
  final Set<String> _hookedTabs = {};

  /// Alert sources being evaluated. A program ringing the bell in a loop would
  /// otherwise start a window-state query per ring; the ones that arrive while
  /// one is pending are the same news.
  final Set<String> _inFlight = {};

  StreamSubscription<String?>? _clicks;

  @override
  void initState() {
    super.initState();
    // Tabs opened before this mounted (the launch shell) emit no change.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanTabs(ref.read(terminalTabsProvider).tabs);
    });
  }

  @override
  void dispose() {
    unawaited(_clicks?.cancel());
    super.dispose();
  }

  bool get _enabled =>
      (ref.read(settingsProvider).value ?? const AppSettingsModel())
          .desktopNotifications;

  /// The root of the pane tree [tabId] is in: what the tab strip selects.
  String _rootOf(String tabId) {
    final tabs = ref.read(terminalTabsProvider).tabs;
    var current = tabId;
    // Bounded by the tab count, so a parent cycle cannot hang this.
    for (var i = 0; i <= tabs.length; i++) {
      final tab = tabs.where((t) => t.id == current).firstOrNull;
      final parent = tab?.splitParentId;
      if (parent == null) return current;
      current = parent;
    }
    return current;
  }

  void _scanTabs(List<TerminalTabSession> tabs) {
    // An agent's mirrored session is not the user's to be told about: its
    // transcript is written by the MCP pool and carries whatever the agent
    // ran.
    final own = [
      for (final tab in tabs)
        if (!tab.isMcp) tab,
    ];

    for (final end in _drops.scan([
      for (final tab in own)
        (id: tab.id, connected: tab.isConnected, cause: tab.disconnectCause),
    ])) {
      final tab = own.firstWhere((t) => t.id == end.id);
      _raise(
        AppAlert(
          kind: end.cause == TerminalDisconnectCause.connectionLost
              ? AppAlertKind.sessionDropped
              : AppAlertKind.sessionEnded,
          tabId: _rootOf(tab.id),
          tabTitle: tab.title,
        ),
      );
    }

    final ids = {for (final tab in own) tab.id};
    _hookedTabs.retainAll(ids);
    for (final tab in own) {
      if (_hookedTabs.add(tab.id)) _hook(tab);
    }
  }

  /// Chains onto the terminal's callbacks rather than replacing them: nothing
  /// owns them today, but a later feature should not be silenced by this.
  void _hook(TerminalTabSession tab) {
    final terminal = tab.terminal;
    final previousBell = terminal.onBell;
    terminal.onBell = () {
      previousBell?.call();
      _raise(
        AppAlert(
          kind: AppAlertKind.terminalBell,
          tabId: _rootOf(tab.id),
          tabTitle: tab.title,
        ),
      );
    };
    final previousNotification = terminal.onNotification;
    terminal.onNotification = (title, body) {
      previousNotification?.call(title, body);
      _raise(
        AppAlert(
          kind: AppAlertKind.terminalNotification,
          tabId: _rootOf(tab.id),
          tabTitle: tab.title,
          title: title,
          body: body,
        ),
      );
    };
  }

  void _scanTunnels(List<ActiveTunnel> tunnels) {
    final failed = _tunnelFailures.scan(tunnels);
    if (failed.isEmpty) return;
    final hosts = ref.read(hostsProvider).value ?? const <HostModel>[];
    for (final tunnel in failed) {
      final route = tunnelRouteLabel(
        type: tunnel.type,
        localPort: tunnel.localPort,
        remoteHost: tunnel.remoteHost,
        remotePort: tunnel.remotePort,
      );
      final host = hosts.where((h) => h.id == tunnel.hostId).firstOrNull;
      _raise(
        AppAlert(
          kind: AppAlertKind.tunnelFailed,
          ruleId: tunnel.ruleId,
          subject: host == null ? route : '${host.label} · $route',
          body: tunnel.error,
        ),
      );
    }
  }

  void _raise(AppAlert alert) {
    if (!mounted) return;
    unawaited(
      _handle(alert).catchError((Object e) {
        debugPrint('[Notifications] $e');
      }),
    );
  }

  Future<void> _handle(AppAlert alert) async {
    final source = '${alert.kind.name}:${alert.tabId ?? alert.ruleId}';
    if (!_inFlight.add(source)) return;
    try {
      final presence = await ref.read(windowPresenceReaderProvider).read();
      if (!mounted) return;

      // The icon is the tray's own state, not a notification: it is raised
      // whether or not notifications are on, and carries no text to leak.
      if (alert.kind.isFailure && !presence.isInFront) {
        ref.read(trayAttentionProvider.notifier).raise();
      }

      if (!_enabled) return;
      final route = currentHostRoute;
      final activeId = ref.read(terminalTabsProvider).activeTabId;
      final request = _policy.evaluate(
        alert,
        NotificationContext(
          window: presence,
          // With no router to ask (a test harness) the terminal is assumed to
          // be the screen, which is the quieter of the two guesses.
          terminalInView: route == null || route.startsWith('/terminal'),
          activeTabId: activeId == null ? null : _rootOf(activeId),
          vaultLocked: isVaultLockedOrUnknown(ref),
        ),
      );
      if (request == null) return;

      final presenter = ref.read(notificationPresenterProvider);
      _clicks ??= presenter.clicks.listen(_onClick);
      await presenter.show(request);
    } finally {
      _inFlight.remove(source);
    }
  }

  void _onClick(String? payload) {
    if (!mounted) return;
    unawaited(
      _handleClick(payload).catchError((Object e) {
        debugPrint('[Notifications] click failed: $e');
      }),
    );
  }

  Future<void> _handleClick(String? payload) async {
    final target = NotificationTarget.parse(payload);
    // A notification outlives the lock it was sent under. Clicked after one,
    // it brings the window up, and the router puts the unlock screen in front
    // of it; nothing is opened behind that.
    if (target == null || isVaultLockedOrUnknown(ref)) {
      await showHostWindow();
      return;
    }
    switch (target) {
      case NotificationTab(:final tabId):
        final open = ref
            .read(terminalTabsProvider)
            .tabs
            .any((tab) => tab.id == tabId);
        if (open) {
          await focusTerminalTab(ref, tabId);
        } else {
          await showHostWindow();
        }
      case NotificationTunnels():
        await showHostWindow();
        goToHostRoute('/tunnels');
    }
  }

  @override
  Widget build(BuildContext context) {
    // `isConnected` is a mutable field, but the notifier re-emits the tab list
    // whenever one flips, which is what lets a dropped session be seen here.
    ref.listen(terminalTabsProvider, (_, next) => _scanTabs(next.tabs));
    // Read at event time, but kept loaded: the provider disposes when nothing
    // listens, and a change made while the window is hidden must not land on a
    // disposed notifier.
    ref.listen(settingsProvider, (_, _) {});
    ref.listen(
      activeTunnelsStreamProvider,
      (_, next) => _scanTunnels(next.value ?? const <ActiveTunnel>[]),
    );
    return widget.child;
  }
}
