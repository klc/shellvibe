import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/platform_capabilities.dart';
import '../../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../features/tunnels/presentation/providers/tunnels_providers.dart';
import 'disconnect_all.dart';
import 'foreground_service_controller.dart';
import 'foreground_service_gateway.dart';
import 'foreground_service_state.dart';

/// Whether this platform has the foreground service to run: Android only.
/// iOS suspends an app however it is asked not to, and a desktop keeps running
/// behind its tray.
bool get supportsForegroundService =>
    !kIsWeb && runtimeTargetPlatform == TargetPlatform.android;

/// The platform half of the service, overridable so a test can watch what the
/// service is asked to do without a native plugin behind it.
final foregroundServiceGatewayProvider = Provider<ForegroundServiceGateway>(
  (ref) => PluginForegroundServiceGateway(),
);

/// How many sessions and tunnels are live, as the notification counts them.
///
/// A provider of its own, rather than the host watching the two sources, so
/// that what the host reacts to is the *counts*. The tunnel list is re-emitted
/// on every speed tick and the tab list whenever any tab changes; a value that
/// compares equal is not a change to Riverpod, so neither reaches the service.
final foregroundServiceCountsProvider = Provider<ServiceCounts>((ref) {
  final tabs = ref.watch(terminalTabsProvider.select((state) => state.tabs));
  final tunnels = ref.watch(activeTunnelsStreamProvider).value ?? const [];
  return deriveServiceCounts(tabs: tabs, tunnels: tunnels);
});

/// Keeps an Android foreground service running for as long as a terminal
/// session is connected or a tunnel is up, so the process — and the sockets
/// the main isolate holds in it — is not suspended when the app leaves the
/// screen.
///
/// Sits above the router, like [QuickActionsHost] does on the same platform,
/// so it outlives every route.
///
/// The vault's auto-lock is not its business and is not touched: the vault
/// still locks on schedule, and sessions carrying on behind a locked vault is
/// the same as a desktop keeping them behind the tray.
///
/// Android only. The caller decides; this widget does not check.
class ForegroundServiceHost extends ConsumerStatefulWidget {
  const ForegroundServiceHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ForegroundServiceHost> createState() =>
      _ForegroundServiceHostState();
}

class _ForegroundServiceHostState extends ConsumerState<ForegroundServiceHost> {
  late final ForegroundServiceController _controller;

  /// Set once the platform side is set up. Counts that arrive before that are
  /// not lost: the current ones are handed over the moment it is.
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = ForegroundServiceController(
      gateway: ref.read(foregroundServiceGatewayProvider),
    );
    unawaited(
      _controller
          .initialize(onDisconnectAll: () => unawaited(_disconnectAll()))
          .then((_) {
            if (!mounted) return;
            _ready = true;
            _controller.update(ref.read(foregroundServiceCountsProvider));
          })
          .catchError((Object error) {
            debugPrint('[ForegroundService] could not start: $error');
          }),
    );
  }

  @override
  void dispose() {
    // The service outliving the app would be a notification for sockets that
    // are gone.
    unawaited(_controller.dispose());
    super.dispose();
  }

  /// The notification's "Disconnect all": what tapping close on every tab and
  /// stop on every tunnel would do, through the notifiers those buttons use.
  Future<void> _disconnectAll() async {
    if (!mounted) return;
    // The tunnels notifier disposes itself once nobody listens, and stopRule
    // reads providers after awaiting the engine, which a disposed notifier may
    // not do. Holding a listener for the length of the call is what keeps it
    // alive when no Tunnels screen is open.
    final keepAlive = ref.listenManual(tunnelsProvider, (_, _) {});
    try {
      await disconnectAll(
        tabIds: tabIdsToDisconnect(ref.read(terminalTabsProvider).tabs),
        ruleIds: tunnelRuleIdsToStop(
          ref.read(activeTunnelsStreamProvider).value ?? const [],
        ),
        closeTab: ref.read(terminalTabsProvider.notifier).closeTab,
        stopTunnel: ref.read(tunnelsProvider.notifier).stopRule,
      );
    } finally {
      keepAlive.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(foregroundServiceCountsProvider, (_, counts) {
      if (_ready) _controller.update(counts);
    });
    return widget.child;
  }
}
