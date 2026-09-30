import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/platform_capabilities.dart';
import '../../features/bookmarks/presentation/notifiers/bookmarks_notifier.dart';
import '../../features/bookmarks/domain/models/bookmark_model.dart';
import '../../features/hosts/domain/services/host_launcher.dart';
import '../../features/hosts/presentation/notifiers/hosts_notifier.dart';
import '../../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../features/terminal/presentation/widgets/select_host_panel.dart';
import '../../features/vault/presentation/notifiers/vault_notifier.dart';
import '../../shared/providers/workspace_provider.dart';
import '../router/app_router.dart';
import '../widgets/adaptive_modal.dart';
import 'app_shortcuts.dart';
import 'quick_actions_controller.dart';

/// The platform half of the app-icon menu, overridable so a test can watch
/// what is registered without a native plugin behind it.
final quickActionsGatewayProvider = Provider<QuickActionsGateway>(
  (ref) => const PluginQuickActionsGateway(),
);

/// Mounts the app-icon shortcuts (long-press on the launcher icon) for the
/// life of the app.
///
/// Sits above the router, like the MCP approval host, so it outlives every
/// route. That also means it has no navigator of its own: anything that needs
/// one goes through [rootNavigatorKey].
///
/// Mobile only. The caller decides; this widget does not check.
class QuickActionsHost extends ConsumerStatefulWidget {
  const QuickActionsHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<QuickActionsHost> createState() => _QuickActionsHostState();
}

class _QuickActionsHostState extends ConsumerState<QuickActionsHost> {
  late final QuickActionsController _controller;
  late final QuickActionDispatcher _dispatcher;

  /// How many frames a waiting press is retried for while only the navigator
  /// is missing. Bounded so a navigator that never appears cannot keep the
  /// engine producing frames.
  static const int _maxFlushFrames = 120;
  int _flushFrames = 0;

  @override
  void initState() {
    super.initState();
    _controller = QuickActionsController(
      gateway: ref.read(quickActionsGatewayProvider),
    );
    _dispatcher = QuickActionDispatcher(canRun: _canRun, run: _run);
    unawaited(
      _controller
          .initialize(_dispatcher.submit)
          .then((_) => _scheduleFlush())
          .catchError((Object error) {
            debugPrint('[QuickActions] could not start: $error');
          }),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncShortcuts());
  }

  @override
  void dispose() {
    _controller.dispose();
    _dispatcher.clear();
    super.dispose();
  }

  VaultState? get _vault => ref.read(vaultProvider).value;

  /// Whether the vault is closed, or closing. Unresolved is not locked — the
  /// shortcuts wait for an answer rather than guess one.
  bool get _vaultLocked {
    final vault = _vault;
    return vault != null &&
        (vault.status == VaultStatus.locked || vault.isLocking);
  }

  /// A press runs only once the vault has said it is open (or has no lock to
  /// open) and the router has a navigator to put the result on. Running it
  /// any sooner would either bypass the unlock screen or have nowhere to go.
  bool _canRun() {
    final vault = _vault;
    if (vault == null || _vaultLocked) return false;
    return rootNavigatorKey.currentContext?.mounted ?? false;
  }

  /// Retries a waiting press on the coming frames: at a cold start the vault
  /// can be open before the first frame has built the navigator, and nothing
  /// else would wake the dispatcher.
  void _scheduleFlush() {
    if (!mounted) return;
    _dispatcher.flush();
    if (!_dispatcher.hasPending || _vault == null || _vaultLocked) return;
    if (_flushFrames++ >= _maxFlushFrames) return;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _scheduleFlush())
      ..scheduleFrame();
  }

  void _syncShortcuts() {
    if (!mounted) return;
    final vault = _vault;
    if (vault == null) return;
    final locked = _vaultLocked;

    final hosts = ref.read(hostsProvider).value;
    final bookmarks = ref.read(bookmarksProvider).value;
    if (!locked && (hosts == null || bookmarks == null)) return;

    _controller.update(
      buildAppShortcuts(
        hosts: hosts ?? const [],
        bookmarkedHostIds: [
          for (final bookmark in bookmarks ?? const <BookmarkModel>[])
            if (bookmark.hostId != null) bookmark.hostId!,
        ],
        locked: locked,
        supportsLocalTerminal: supportsLocalShell,
      ),
      // Taking host names off the menu cannot wait for a debounce.
      immediate: locked,
    );
  }

  Future<void> _run(QuickAction action) async {
    try {
      switch (action) {
        case ConnectHostAction(:final hostId):
          await _connectHost(hostId);
        case OpenLocalTerminalAction():
          if (!supportsLocalShell) return;
          ref.read(terminalTabsProvider.notifier).openLocalTab();
          final context = _navigatorContext();
          if (context != null) GoRouter.maybeOf(context)?.go('/terminal');
        case QuickConnectAction():
          _showQuickConnect();
      }
    } on Object catch (error, stackTrace) {
      debugPrint('[QuickActions] could not run $action: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  BuildContext? _navigatorContext() {
    final context = rootNavigatorKey.currentContext;
    return context != null && context.mounted ? context : null;
  }

  Future<void> _connectHost(String hostId) async {
    // By id, not from the list on screen: the shortcut was registered for
    // whichever workspace was active then, and the host may since have moved
    // on or been deleted — in which case there is nothing to do.
    final host = await ref.read(hostsRepositoryProvider).getHostById(hostId);
    if (host == null) return;
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await HostLauncher(context: context, ref: ref).connect(host);
  }

  void _showQuickConnect() {
    final context = _navigatorContext();
    if (context == null) return;
    GoRouter.maybeOf(context)?.go('/terminal');
    unawaited(
      showAdaptivePanel<void>(
        context: context,
        title: 'Connect to Host',
        desktopHeight: 420,
        builder: (panelContext) => SelectHostPanel(
          onSelected: (host) async {
            Navigator.of(panelContext).pop();
            final launchContext = _navigatorContext();
            if (launchContext == null) return;
            await HostLauncher(context: launchContext, ref: ref).connect(host);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // What the menu shows follows what the user has starred, in the workspace
    // they are in (both providers reload when it changes).
    ref.listen(hostsProvider, (_, _) => _syncShortcuts());
    ref.listen(bookmarksProvider, (_, _) => _syncShortcuts());
    ref.listen(activeWorkspaceIdProvider, (_, _) => _syncShortcuts());
    ref.listen(vaultProvider, (_, _) {
      _syncShortcuts();
      // After the frame: unlocking also moves the router off the unlock
      // screen, and the press should land on what it leaves behind.
      _flushFrames = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleFlush());
    });
    return widget.child;
  }
}
