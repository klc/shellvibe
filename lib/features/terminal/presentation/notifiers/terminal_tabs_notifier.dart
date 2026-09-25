import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm3/xterm.dart';

import '../../../../core/network/device_link/device_link_local_session_transport.dart';
import '../../../../core/network/device_link/device_link_server.dart';
import '../../../../core/network/device_link/device_link_session_transport.dart';
import '../../../../core/network/local_pty_manager.dart';
import '../../../../core/network/providers/network_providers.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../../settings/domain/models/app_settings_model.dart';
import '../../../settings/presentation/notifiers/settings_notifier.dart';
import '../../../device_link/data/repositories/device_link_pairing_repository.dart';
import '../../../vault/data/repositories/vault_env_repository.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../../vault/presentation/notifiers/vault_env_vars_notifier.dart';
import '../../../vault/presentation/notifiers/vault_notifier.dart';
import '../../domain/models/terminal_palette_data.dart';
import '../../domain/models/terminal_tab_session.dart';
import '../../domain/services/broadcast_input_router.dart';
import '../../domain/services/device_link_server_host.dart';
import '../../domain/services/terminal_pane_layout.dart';
import '../../domain/services/terminal_session_connector.dart';
import 'terminal_tabs_state.dart';

export 'terminal_tabs_state.dart';

part 'terminal_tabs_notifier.g.dart';

/// Maps the runtime platform onto the terminal's platform so key input is
/// decoded with host-platform semantics.
///
/// Without this the terminal stays `TerminalTargetPlatform.unknown`, which
/// takes the non-macOS branch in the input handlers: on macOS the Turkish Q
/// layout composes `@` with Option+Q, but `unknown` treats Option as Meta
/// and sends `ESC + @`, so the @ never reaches the shell.
TerminalTargetPlatform _terminalTargetPlatform() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS => TerminalTargetPlatform.macos,
    TargetPlatform.iOS => TerminalTargetPlatform.ios,
    TargetPlatform.android => TerminalTargetPlatform.android,
    TargetPlatform.windows => TerminalTargetPlatform.windows,
    TargetPlatform.linux => TerminalTargetPlatform.linux,
    TargetPlatform.fuchsia => TerminalTargetPlatform.fuchsia,
  };
}

@Riverpod(keepAlive: true)
class TerminalTabsNotifier extends _$TerminalTabsNotifier {
  final Set<TerminalTabSession> _ownedTabs = {};
  final Map<String, DeviceLinkLocalSessionTransport> _deviceLinkTransports = {};
  final BroadcastInputRouter _broadcastRouter = BroadcastInputRouter();
  final TerminalPaneLayout _paneLayout = TerminalPaneLayout();

  /// Per-tab teardown that has to run *before* the tab's own dispose, for
  /// tabs whose real session lives somewhere else: a Device Link peer, an MCP
  /// session in the pool. Keyed by tab id and removed as it is invoked, which
  /// is what keeps "close the tab, which closes the session, which closes the
  /// tab" from looping.
  final Map<String, FutureOr<void> Function()> _tabCloseCallbacks = {};

  /// Establishes and reconnects SSH/Mosh sessions. Constructed once in
  /// [build] with callbacks into this notifier's `state` and `ref`, so the
  /// actual connect/reconnect machinery lives outside Riverpod. See
  /// [TerminalSessionConnector].
  late final TerminalSessionConnector _sessionConnector;

  /// Hosts the desktop-side Device Link listener. Constructed once in
  /// [build]; see [DeviceLinkServerHost].
  late final DeviceLinkServerHost _deviceLinkHost;

  /// Set when the provider is torn down.
  ///
  /// A local shell is attached after an await — its reading isolate has to
  /// come up first — so the pane it was starting for can be gone by the time
  /// it is ready, and touching `state` past disposal throws.
  bool _notifierDisposed = false;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool get _isVaultAvailable {
    final vault = ref.read(vaultProvider);
    return _vaultAllowsDeviceLink(vault);
  }

  bool _vaultAllowsDeviceLink(AsyncValue<VaultState> vault) {
    return vault.hasValue &&
        !vault.isLoading &&
        !vault.hasError &&
        vault.value!.allowsDeviceLink;
  }

  @override
  TerminalTabsState build() {
    // Interceptors read the notifier's live selection, never a snapshot.
    _broadcastRouter.forwardCallback = _broadcastFrom;
    _sessionConnector = TerminalSessionConnector(
      knownHostsDao: () => ref.read(knownHostsDaoProvider),
      hostsRepository: () => ref.read(hostsRepositoryProvider),
      fetchIdentityById: (id) =>
          ref.read(vaultRepositoryProvider).getIdentityById(id),
      decryptIdentityById: (id) =>
          ref.read(identitiesProvider.notifier).getDecryptedIdentity(id),
      findTab: tabById,
      tabIsOpen: (tabId) => state.tabs.any((t) => t.id == tabId),
      notifyChanged: () => state = state.copyWith(tabs: [...state.tabs]),
      syncBroadcast: _syncBroadcast,
      watchConnectivity: _watchConnectivity,
    );
    _deviceLinkHost = DeviceLinkServerHost(
      pairingRepository: () => ref.read(deviceLinkPairingRepositoryProvider),
      secureStorage: () => ref.read(secureStorageServiceProvider),
      isVaultAvailable: () => _isVaultAvailable,
      sessionTransportsProvider: deviceLinkSessionTransports,
    );
    ref.listen(vaultProvider, (_, next) {
      if (_vaultAllowsDeviceLink(next)) return;
      unawaited(stopDeviceLinkServer());
    });
    ref.onDispose(() {
      _notifierDisposed = true;
      unawaited(_connectivitySub?.cancel() ?? Future.value());
      _connectivitySub = null;
      // Reading `state` is forbidden during life-cycles; drop interceptors
      // from the owned-tab set instead.
      _broadcastRouter.restoreAll(_ownedTabs.toList());
      for (final tab in _ownedTabs.toList()) {
        tab.dispose();
      }
      _ownedTabs.clear();
      _deviceLinkTransports.clear();
      // The owners these call back into are being torn down alongside this
      // notifier, so drop them rather than invoking them.
      _tabCloseCallbacks.clear();
      _deviceLinkHost.dispose();
    });
    return const TerminalTabsState();
  }

  /// Starts watching for network changes, the roaming trigger the whole
  /// protocol exists for: Wi-Fi to cellular, a tunnel, a lift. The manager
  /// debounces the burst of events one transition produces, so this stays a
  /// plain forward.
  ///
  /// Subscribed on the first Mosh session rather than at build time, so the
  /// platform channel is never touched by the SSH-only and local-shell paths
  /// that make up every other tab.
  ///
  /// Wrapped in a try: on a platform without an implementation, a terminal that
  /// refuses to open because nobody could tell it about the network would be a
  /// far worse failure than a Mosh session that only rehomes on resume.
  void _watchConnectivity() {
    if (_connectivitySub != null) return;
    try {
      _connectivitySub = Connectivity().onConnectivityChanged.listen(
        (_) => rehomeMoshSessions(),
        onError: (_) {},
      );
    } catch (_) {
      _connectivitySub = null;
    }
  }

  /// Asks every live Mosh session to rebind onto the current network path.
  ///
  /// Called on a connectivity change and on app resume — iOS tears the UDP
  /// socket down while suspended, so coming back to the foreground needs a
  /// rebind even when the network never changed.
  void rehomeMoshSessions() {
    for (final tab in _ownedTabs) {
      final manager = tab.moshSessionManager;
      if (manager == null || !manager.isConnected) continue;
      unawaited(manager.rehome());
    }
  }

  Future<void> openTabForHost(
    HostModel host, {
    IdentityModel? identity,
    HostKeyPromptCallback? onHostKeyPrompt,
  }) async {
    final tabId = const Uuid().v4();
    final terminal = Terminal(
      maxLines: 10000,
      platform: _terminalTargetPlatform(),
    );

    final newTab = TerminalTabSession(
      id: tabId,
      title: host.label,
      sessionType: TerminalSessionType.ssh,
      host: host,
      identity: identity,
      terminal: terminal,
      isConnecting: true,
      hostKeyPromptCallback: onHostKeyPrompt,
    );
    _ownedTabs.add(newTab);

    final updatedTabs = [...state.tabs, newTab];
    state = state.copyWith(tabs: updatedTabs, activeTabId: tabId);

    await _sessionConnector.connectSshTab(
      newTab,
      host,
      identity,
      onHostKeyPrompt,
    );
  }

  /// Re-establishes the SSH session of a tab whose connection dropped or
  /// failed, re-reading the host so any edit made since the tab was opened
  /// applies, and reusing the stored host key prompt callback. The old bridge
  /// and manager are torn down first so a single live session per tab is
  /// preserved. See [TerminalSessionConnector.reconnectTab].
  Future<void> reconnectTab(String tabId) =>
      _sessionConnector.reconnectTab(tabId);

  void openLocalTab({String? title}) {
    final tabId = const Uuid().v4();
    final terminal = Terminal(
      maxLines: 10000,
      platform: _terminalTargetPlatform(),
    );

    final newTab = TerminalTabSession(
      id: tabId,
      title: title ?? 'Local Shell',
      sessionType: TerminalSessionType.local,
      terminal: terminal,
      isConnecting: true,
    );

    final updatedTabs = [...state.tabs, newTab];
    state = state.copyWith(tabs: updatedTabs, activeTabId: tabId);

    // The shell is read on its own isolate, and spawning one is asynchronous.
    // The tab is already on screen marked connecting, so the attach finishes
    // in the background rather than making every caller of this await a
    // process start.
    unawaited(_attachLocalShell(newTab));
  }

  /// Environment a local shell starts with, on top of the app's own.
  ///
  /// Vault environment variables come first and the built-ins are applied on
  /// top, so a stored variable can never shadow one of these — not that it
  /// could anyway, since the vault form and repository both reject the
  /// reserved names.
  ///
  /// `TERM_THEME` tells CLI tools whether they paint on a light or a dark
  /// background. It follows the terminal palette rather than the app theme: a
  /// light app can host a dark terminal. It is fixed at spawn, since a running
  /// process's environment cannot be changed from outside, so a palette switch
  /// reaches the shells opened after it.
  ///
  /// Settings not loaded yet fall back to the defaults, as the terminal view
  /// does, rather than holding the shell back on a storage read.
  ///
  /// A locked vault or an undecryptable row never blocks the shell: both are
  /// announced with one dim line written to [terminal] *before* this returns,
  /// so it lands ahead of the shell's own first output, and the shell starts
  /// either way.
  Future<Map<String, String>> _localShellEnvironment(Terminal terminal) async {
    final settings =
        ref.read(settingsProvider).value ?? const AppSettingsModel();
    final isLight = TerminalPaletteData.of(settings.terminalPalette).isLight;
    final builtins = {'TERM_THEME': isLight ? 'light' : 'dark'};

    final VaultEnvShellResolution resolved;
    try {
      resolved = await ref
          .read(vaultEnvRepositoryProvider)
          .resolveForShell(workspaceId: ref.read(activeWorkspaceIdProvider));
    } catch (_) {
      // Whatever went wrong reading the vault, it is no reason to withhold the
      // shell itself.
      terminal.write(
        '\x1b[2m[Environment variables could not be loaded]\x1b[0m\r\n',
      );
      return builtins;
    }

    if (resolved.vaultLocked) {
      terminal.write(
        '\x1b[2m[Vault locked: environment variables not loaded]\x1b[0m\r\n',
      );
    }
    if (resolved.undecryptable > 0) {
      terminal.write(
        '\x1b[2m[${resolved.undecryptable} environment variable(s) could '
        'not be decrypted]\x1b[0m\r\n',
      );
    }

    return {...resolved.vars, ...builtins};
  }

  /// Starts the shell behind [tab] and wires it up once it exists.
  Future<void> _attachLocalShell(TerminalTabSession tab) async {
    final terminal = tab.terminal;
    try {
      final manager = ref.read(localPtyManagerProvider);
      final bridge = await manager.startAndBridge(
        terminal,
        environment: await _localShellEnvironment(terminal),
        rows: terminal.viewHeight,
        columns: terminal.viewWidth,
      );

      if (_notifierDisposed) {
        // The pane went away while its process was starting; nothing is left
        // to attach it to, and touching `state` past disposal throws.
        await bridge?.dispose();
        return;
      }

      tab.ptyBridge = bridge;
      if (bridge != null) _registerDeviceLinkTransport(tab, bridge);
      // See _connectSsh: the first layout resize happens before the bridge
      // wires `onResize`, so push the current size once by hand.
      bridge?.resizeTerminal(terminal.viewWidth, terminal.viewHeight);
      tab.isConnecting = false;
      tab.isConnected = bridge != null;
      if (bridge == null) {
        tab.errorMessage = 'Failed to start local terminal session';
      }
    } catch (e) {
      if (_notifierDisposed) return;
      tab.isConnecting = false;
      tab.isConnected = false;
      tab.errorMessage = e.toString();
    }

    if (_notifierDisposed) return;
    state = state.copyWith(tabs: [...state.tabs]);
    // Wire broadcast if this pane is already part of the selection.
    _syncBroadcast();
  }

  /// Opens the read-only tab that mirrors an agent's MCP session, and returns
  /// its id.
  ///
  /// The tab owns no transport: the MCP session pool writes into [terminal]
  /// and the shell lives in the pool, which is why this takes an [onClose]
  /// rather than building a bridge. It is registered like a Device Link tab
  /// so the existing close cascade tears the session down with the tab —
  /// docs/mcp_plan.md's "sekmeyi kapatmak oturumu öldürür".
  String openMcpTab({
    required String mcpSessionId,
    required String title,
    required FutureOr<void> Function() onClose,
  }) {
    final tabId = const Uuid().v4();
    final tab = TerminalTabSession(
      id: tabId,
      title: title,
      sessionType: TerminalSessionType.ssh,
      mcpSessionId: mcpSessionId,
      terminal: Terminal(maxLines: 10000, platform: _terminalTargetPlatform()),
      isConnected: true,
    );
    _ownedTabs.add(tab);
    _tabCloseCallbacks[tabId] = onClose;
    // Deliberately does not steal focus by activating itself: an agent
    // opening a session while the user is typing in another tab must not
    // yank them out of it. The tab appears, badged, and waits to be clicked.
    state = state.copyWith(tabs: [...state.tabs, tab]);
    return tabId;
  }

  /// The tab with [tabId], or null if it is not open.
  ///
  /// Public because collaborators outside the notifier — the MCP session
  /// mirror, which writes an agent's transcript into a tab it did not create
  /// — need the tab without reaching into `state`, which Riverpod keeps
  /// protected for good reason.
  TerminalTabSession? tabById(String tabId) {
    for (final tab in state.tabs) {
      if (tab.id == tabId) return tab;
    }
    return null;
  }

  /// Closes an MCP tab because its *session* ended, rather than because the
  /// user closed it. Dropping the close callback first is what stops this
  /// from calling back into the pool that is already tearing the session
  /// down.
  Future<void> closeMcpTab(String tabId) async {
    _tabCloseCallbacks.remove(tabId);
    await closeTab(tabId);
  }

  Future<void> closeTab(String tabId) async {
    final index = state.tabs.indexWhere((t) => t.id == tabId);
    if (index == -1) return;

    // Cascade: split panes are children of the closed tab and must be torn
    // down with it, otherwise their PTY/SSH sessions keep running orphaned.
    final closingTabs = <TerminalTabSession>[state.tabs[index]];
    var foundChild = true;
    while (foundChild) {
      foundChild = false;
      for (final tab in state.tabs) {
        if (tab.splitParentId != null &&
            closingTabs.any((c) => c.id == tab.splitParentId) &&
            !closingTabs.any((c) => c.id == tab.id)) {
          closingTabs.add(tab);
          foundChild = true;
        }
      }
    }

    final closingIds = closingTabs.map((t) => t.id).toSet();
    final remainingTabs = state.tabs
        .where((t) => !closingIds.contains(t.id))
        .toList();
    String? newActiveId = state.activeTabId;

    if (closingIds.contains(state.activeTabId)) {
      newActiveId = _paneLayout.focusAfterClose(
        closedTab: state.tabs[index],
        oldTabs: state.tabs,
        remainingTabs: remainingTabs,
      );
    }

    final prunedSelection = state.selectedPaneIds
        .where((id) => !closingIds.contains(id))
        .toSet();

    state = state.copyWith(
      tabs: remainingTabs,
      activeTabId: newActiveId,
      clearActiveTabId: newActiveId == null,
      selectedPaneIds: prunedSelection,
    );
    _syncBroadcast();

    for (final tab in closingTabs) {
      final onClose = _tabCloseCallbacks.remove(tab.id);
      try {
        await onClose?.call();
      } finally {
        await tab.dispose();
        _deviceLinkTransports.remove(tab.id);
        _ownedTabs.remove(tab);
      }
    }
  }

  /// Closes every tab except the one rooted at [tabId].
  Future<void> closeOtherTabs(String tabId) =>
      _closeTabsAround(tabId, left: true, right: true);

  /// Closes the tabs before the one rooted at [tabId] in the strip.
  Future<void> closeTabsToLeft(String tabId) =>
      _closeTabsAround(tabId, left: true, right: false);

  /// Closes the tabs after the one rooted at [tabId] in the strip.
  Future<void> closeTabsToRight(String tabId) =>
      _closeTabsAround(tabId, left: false, right: true);

  /// Closes root tabs on either side of [tabId], each through [closeTab] so
  /// its split panes and sessions go with it.
  ///
  /// Focus moves to [tabId] first when the focused pane is about to close:
  /// the tab that was right-clicked is the one being kept, so it is where the
  /// user is looking, not wherever [closeTab]'s own fallback would land.
  Future<void> _closeTabsAround(
    String tabId, {
    required bool left,
    required bool right,
  }) async {
    final roots = [
      for (final tab in state.tabs)
        if (tab.splitParentId == null) tab.id,
    ];
    final index = roots.indexOf(tabId);
    if (index == -1) return;
    final closing = [
      if (left) ...roots.sublist(0, index),
      if (right) ...roots.sublist(index + 1),
    ];
    if (closing.isEmpty) return;

    final active = state.activeTab;
    if (active != null &&
        closing.contains(_paneLayout.rootIdOf(active, state.tabs))) {
      setActiveTab(tabId);
    }
    for (final id in closing) {
      await closeTab(id);
    }
  }

  /// Closes a single pane, keeping the rest of its tab alive.
  ///
  /// Unlike [closeTab] this never cascades: the panes split off [paneId] are
  /// promoted into the slot it occupied. The last child (the pane laid out
  /// directly against [paneId], see the split fold in the tab view) becomes the
  /// heir and takes the closed pane's parent, direction and ratio; the earlier
  /// children hang off the heir, which preserves both their relative nesting
  /// and their on-screen order. Closing the root pane of a tab therefore keeps
  /// the tab open with the heir as its new root.
  Future<void> closePane(String paneId) async {
    final index = state.tabs.indexWhere((t) => t.id == paneId);
    if (index == -1) return;

    final pane = state.tabs[index];
    final children = state.tabs
        .where((t) => t.splitParentId == paneId)
        .toList();

    if (children.isEmpty) {
      // A leaf pane: closing it is closing a tab with nothing to cascade to.
      await closeTab(paneId);
      return;
    }

    final remainingTabs = _paneLayout.promoteHeir(state.tabs, pane, children);
    final heir = children.last;

    final newActiveId = state.activeTabId == paneId
        ? heir.id
        : state.activeTabId;
    final prunedSelection = state.selectedPaneIds
        .where((id) => id != paneId)
        .toSet();

    state = state.copyWith(
      tabs: remainingTabs,
      activeTabId: newActiveId,
      selectedPaneIds: prunedSelection,
    );
    _syncBroadcast();

    final onClose = _tabCloseCallbacks.remove(paneId);
    try {
      await onClose?.call();
    } finally {
      await pane.dispose();
      _deviceLinkTransports.remove(paneId);
      _ownedTabs.remove(pane);
    }
  }

  /// Supplies stable live local-session adapters to the Device Link server.
  /// Core transport code uses these adapters without depending on Riverpod or
  /// BuildContext.
  List<DeviceLinkSessionTransport> deviceLinkSessionTransports() =>
      List.unmodifiable(_deviceLinkTransports.values);

  DeviceLinkSessionTransport? deviceLinkSessionTransport(String sessionId) =>
      _deviceLinkTransports[sessionId];

  Stream<void> get deviceLinkPairingEvents => _deviceLinkHost.pairingEvents;

  /// Disconnects the phone currently owning [sessionId], if any. Closing the
  /// Device Link connection deliberately goes through the server's normal
  /// release path so the desktop terminal dimensions are restored as well.
  Future<void> disconnectDeviceLink(String sessionId) async {
    await _deviceLinkTransports[sessionId]?.disconnect();
  }

  /// Registers a mobile Device Link session in the same owned-tab collection
  /// as local and SSH sessions. The linked screen can therefore reuse the
  /// terminal lifecycle without creating a parallel tab store.
  void registerDeviceLinkSession(
    TerminalTabSession tab, {
    FutureOr<void> Function()? onClose,
  }) {
    if (_ownedTabs.contains(tab)) return;
    if (state.tabs.any((candidate) => candidate.id == tab.id)) {
      throw StateError('A terminal tab with id ${tab.id} already exists');
    }
    _ownedTabs.add(tab);
    if (onClose != null) _tabCloseCallbacks[tab.id] = onClose;
    state = state.copyWith(tabs: [...state.tabs, tab], activeTabId: tab.id);
  }

  /// Starts (or reuses) the desktop-side Device Link listener and creates the
  /// short-lived QR payload used by the first pairing flow. See
  /// [DeviceLinkServerHost.createPairingPayload].
  Future<DeviceLinkQrPayload> createDeviceLinkPairingPayload() =>
      _deviceLinkHost.createPairingPayload();

  /// Ensures the desktop listener exists when a previous QR pairing is
  /// already persisted. A clean install must not open a LAN listener merely
  /// because the app was launched.
  Future<void> ensureDeviceLinkServerForPairedDevices() async {
    if (!supportsLocalShell) return;
    await _deviceLinkHost.ensureServerForPairedDevices();
  }

  /// Stops the Device Link listener, all authenticated connections, and its
  /// mDNS advertisement. See [DeviceLinkServerHost.stop].
  Future<void> stopDeviceLinkServer() => _deviceLinkHost.stop();

  @visibleForTesting
  bool get isDeviceLinkServerRunning => _deviceLinkHost.isRunning;

  @visibleForTesting
  bool get deviceLinkVaultAvailable => _isVaultAvailable;

  void _registerDeviceLinkTransport(
    TerminalTabSession tab,
    TerminalLocalPtyBridge bridge,
  ) {
    final transport = DeviceLinkLocalSessionTransport(
      sessionId: tab.id,
      title: tab.title,
      terminal: tab.terminal,
      ptyBridge: bridge,
      attachSession: (deviceId, columns, rows) => tab.attachDeviceLink(
        deviceId: deviceId,
        columns: columns,
        rows: rows,
      ),
      detachSession: tab.detachDeviceLink,
      resizeSession: tab.resizeTerminal,
      onStateChanged: () {
        if (state.tabs.any((candidate) => candidate.id == tab.id)) {
          state = state.copyWith(tabs: [...state.tabs]);
        }
      },
    );
    tab.deviceLinkTransport = transport;
    _deviceLinkTransports[tab.id] = transport;
  }

  void setActiveTab(String tabId) {
    if (state.tabs.any((t) => t.id == tabId)) {
      state = state.copyWith(activeTabId: tabId);
    }
  }

  /// Moves the tab rooted at [tabId] so it becomes the [toIndex]th tab of the
  /// strip, counting root tabs only. See [TerminalPaneLayout.reorderRoots].
  void moveTab(String tabId, int toIndex) {
    final reordered = _paneLayout.reorderRoots(state.tabs, tabId, toIndex);
    if (reordered == null) return;
    state = state.copyWith(tabs: reordered);
  }

  /// Exchanges the positions of two panes of the same tab. See
  /// [TerminalPaneLayout.swapPanes].
  void swapPanes(String paneId, String otherPaneId) {
    final reordered = _paneLayout.swapPanes(state.tabs, paneId, otherPaneId);
    if (reordered == null) return;
    state = state.copyWith(tabs: reordered);
  }

  /// Moves [paneId] out of its slot and splits [targetId] with it, along
  /// [edge]. See [TerminalPaneLayout.dockPane].
  void movePaneTo(String paneId, String targetId, PaneDockEdge edge) {
    if (paneId == targetId) return;

    final result = _paneLayout.dockPane(state.tabs, paneId, targetId, edge);
    if (result == null) return;

    state = state.copyWith(tabs: result);

    if (edge.isLeading) {
      swapPanes(paneId, targetId);
    }
  }

  void setSplitRatio(String tabId, double ratio) {
    final index = state.tabs.indexWhere((t) => t.id == tabId);
    if (index == -1) return;
    state.tabs[index].splitRatio = ratio;
    state = state.copyWith(tabs: [...state.tabs]);
  }

  /// Reconciles installed broadcast interceptors with the current selection.
  void _syncBroadcast() {
    _broadcastRouter.sync(selectedIds: state.selectedPaneIds, tabs: state.tabs);
  }

  /// Forward handler invoked by installed interceptors with the origin pane
  /// id. Reads the live selection, so panes added or removed after an
  /// interceptor was installed are handled correctly.
  void _broadcastFrom(String originId, String data) {
    _broadcastRouter.forwardToOthers(
      originId: originId,
      selectedIds: state.selectedPaneIds,
      tabs: state.tabs,
      data: data,
    );
  }

  /// Toggles [tabId] membership in the broadcast selection.
  void togglePaneSelection(String tabId) {
    // An AI tab can never join a broadcast selection. Broadcast exists to
    // type the same thing into several shells at once, and this one takes no
    // typing at all — letting it in would put user keystrokes into a session
    // the user is only supposed to be watching.
    final tab = state.tabs.where((t) => t.id == tabId).firstOrNull;
    if (tab == null || tab.isMcp) return;
    final updated = {...state.selectedPaneIds};
    if (!updated.add(tabId)) updated.remove(tabId);
    state = state.copyWith(selectedPaneIds: updated);
    _syncBroadcast();
  }

  /// Drops every selected pane, ending broadcast.
  void clearPaneSelection() {
    if (state.selectedPaneIds.isEmpty) return;
    state = state.copyWith(selectedPaneIds: const {});
    _syncBroadcast();
  }

  /// Single entry point for pane taps. A modifier click toggles selection and
  /// makes the pane active (it becomes the broadcast origin); a plain click on
  /// a pane outside the selection clears the selection and focuses that pane.
  void tapPane(String tabId, {required bool broadcastModifier}) {
    if (broadcastModifier) {
      togglePaneSelection(tabId);
    } else if (!state.selectedPaneIds.contains(tabId)) {
      clearPaneSelection();
    }
    setActiveTab(tabId);
  }

  /// Sends [code] to every selected pane (origin included) — the snippet
  /// path while broadcasting.
  void sendTextToSelectedPanes(String code) {
    _broadcastRouter.sendTextToPanes(
      selectedIds: state.selectedPaneIds,
      tabs: state.tabs,
      text: code,
    );
  }

  /// Opens a new pane inside the split tree of [parentTabId].
  ///
  /// With [host] the pane connects to that host instead of inheriting the
  /// parent's session, so one tab can hold panes on different connections.
  /// Without it the pane mirrors the parent (see below).
  Future<void>? splitTab(
    String parentTabId, {
    Axis direction = Axis.horizontal,
    HostModel? host,
    IdentityModel? identity,
    HostKeyPromptCallback? onHostKeyPrompt,
  }) {
    final parentIndex = state.tabs.indexWhere((t) => t.id == parentTabId);
    if (parentIndex == -1) return null;

    final parentTab = state.tabs[parentIndex];
    final splitId = const Uuid().v4();
    final terminal = Terminal(
      maxLines: 10000,
      platform: _terminalTargetPlatform(),
    );

    // Without an explicit target a split pane mirrors the session type of the
    // pane it was created from. Splitting an SSH host session opens a second
    // SSH session to the same host rather than a local shell; this also keeps
    // splits working on mobile, where a local PTY is not available.
    final targetHost = host ?? parentTab.host;
    final isSshSplit =
        host != null ||
        (parentTab.sessionType == TerminalSessionType.ssh &&
            parentTab.host != null);

    final splitTab = TerminalTabSession(
      id: splitId,
      // A pane on its own connection is titled after that host; an inherited
      // pane keeps the parent's title with a marker.
      title: host != null ? host.label : '${parentTab.title} (Split)',
      sessionType: isSshSplit
          ? TerminalSessionType.ssh
          : TerminalSessionType.local,
      host: targetHost,
      identity: host != null ? identity : parentTab.identity,
      terminal: terminal,
      splitParentId: parentTabId,
      splitDirection: direction,
      isConnecting: isSshSplit,
      hostKeyPromptCallback: onHostKeyPrompt,
    );
    _ownedTabs.add(splitTab);

    if (isSshSplit) {
      state = state.copyWith(
        tabs: [...state.tabs, splitTab],
        activeTabId: splitId,
      );
      // Returning the connection future lets callers (and tests) await the
      // SSH handshake; UI call sites fire-and-forget via unawaited(...).
      return _sessionConnector.connectSshTab(
        splitTab,
        targetHost!,
        splitTab.identity,
        onHostKeyPrompt,
      );
    }

    state = state.copyWith(
      tabs: [...state.tabs, splitTab],
      activeTabId: splitId,
    );
    // Same shape as the SSH branch above: the pane is on screen and the
    // process is attached to it once its reading isolate is up. Callers that
    // care can await; UI call sites fire and forget.
    return _attachLocalSplit(splitTab);
  }

  /// Starts the shell behind a local split pane and wires it up.
  Future<void> _attachLocalSplit(TerminalTabSession splitTab) async {
    final terminal = splitTab.terminal;
    try {
      final manager = ref.read(localPtyManagerProvider);
      final bridge = await manager.startAndBridge(
        terminal,
        environment: await _localShellEnvironment(terminal),
        rows: terminal.viewHeight,
        columns: terminal.viewWidth,
      );
      if (_notifierDisposed) {
        // The pane went away while its process was starting; nothing is left
        // to attach it to, and touching `state` past disposal throws.
        await bridge?.dispose();
        return;
      }

      splitTab.ptyBridge = bridge;
      if (bridge != null) _registerDeviceLinkTransport(splitTab, bridge);
      bridge?.resizeTerminal(terminal.viewWidth, terminal.viewHeight);
      splitTab.isConnected = bridge != null;
      if (bridge == null) {
        splitTab.errorMessage = 'Failed to start local terminal session';
      }
    } catch (e) {
      if (_notifierDisposed) return;
      splitTab.isConnected = false;
      splitTab.errorMessage = e.toString();
    }

    if (_notifierDisposed) return;
    state = state.copyWith(tabs: [...state.tabs]);
    // Wire broadcast if this pane is already part of the selection.
    _syncBroadcast();
  }
}
