import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dart_mosh/dart_mosh.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm3/xterm.dart';

import '../../../../core/network/device_link/device_link_local_session_transport.dart';
import '../../../../core/network/device_link/device_discovery.dart';
import '../../../../core/network/device_link/device_link_identity.dart';
import '../../../../core/network/device_link/device_link_server.dart';
import '../../../../core/network/device_link/device_link_session_transport.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/local_pty_manager.dart';
import '../../../../core/network/mosh_session_manager.dart';
import '../../../../core/network/providers/network_providers.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/network/terminal_mosh_bridge.dart';
import '../../../../core/network/terminal_ssh_bridge.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../../shared/storage/secure_storage_service.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../../device_link/data/repositories/device_link_pairing_repository.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../../vault/presentation/notifiers/vault_notifier.dart';
import '../../domain/models/terminal_tab_session.dart';
import '../../domain/services/broadcast_input_router.dart';

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

class TerminalTabsState {
  final List<TerminalTabSession> tabs;
  final String? activeTabId;

  /// Panes picked with ⌘+click. When two or more are selected the terminal
  /// broadcasts keyboard input and snippets to all of them.
  final Set<String> selectedPaneIds;

  const TerminalTabsState({
    this.tabs = const [],
    this.activeTabId,
    this.selectedPaneIds = const {},
  });

  /// True when broadcast input is live (two or more panes selected).
  bool get isBroadcasting => selectedPaneIds.length >= 2;

  TerminalTabSession? get activeTab {
    if (activeTabId == null) return null;
    try {
      return tabs.firstWhere((t) => t.id == activeTabId);
    } catch (_) {
      return null;
    }
  }

  TerminalTabsState copyWith({
    List<TerminalTabSession>? tabs,
    String? activeTabId,
    bool clearActiveTabId = false,
    Set<String>? selectedPaneIds,
  }) {
    return TerminalTabsState(
      tabs: tabs ?? this.tabs,
      activeTabId: clearActiveTabId ? null : (activeTabId ?? this.activeTabId),
      selectedPaneIds: selectedPaneIds ?? this.selectedPaneIds,
    );
  }
}

@Riverpod(keepAlive: true)
class TerminalTabsNotifier extends _$TerminalTabsNotifier {
  final Set<TerminalTabSession> _ownedTabs = {};
  final Map<String, DeviceLinkLocalSessionTransport> _deviceLinkTransports = {};
  final StreamController<void> _deviceLinkPairingEvents =
      StreamController<void>.broadcast();
  final BroadcastInputRouter _broadcastRouter = BroadcastInputRouter();

  /// Per-tab teardown that has to run *before* the tab's own dispose, for
  /// tabs whose real session lives somewhere else: a Device Link peer, an MCP
  /// session in the pool. Keyed by tab id and removed as it is invoked, which
  /// is what keeps "close the tab, which closes the session, which closes the
  /// tab" from looping.
  final Map<String, FutureOr<void> Function()> _tabCloseCallbacks = {};
  DeviceLinkServer? _deviceLinkServer;
  nsd.Registration? _deviceLinkMdnsRegistration;
  Future<DeviceLinkServer>? _deviceLinkServerStartup;
  Future<void>? _deviceLinkServerStop;
  int _deviceLinkLifecycleGeneration = 0;

  /// Set when the provider is torn down.
  ///
  /// A local shell is attached after an await — its reading isolate has to
  /// come up first — so the pane it was starting for can be gone by the time
  /// it is ready, and touching `state` past disposal throws.
  bool _notifierDisposed = false;

  bool _deviceLinkDisposed = false;

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
    ref.listen(vaultProvider, (_, next) {
      if (_vaultAllowsDeviceLink(next)) return;
      unawaited(stopDeviceLinkServer());
    });
    ref.onDispose(() {
      _notifierDisposed = true;
      _deviceLinkDisposed = true;
      _deviceLinkLifecycleGeneration++;
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
      unawaited(_deviceLinkPairingEvents.close());
      final server = _deviceLinkServer;
      _deviceLinkServer = null;
      _deviceLinkServerStartup = null;
      if (server != null) unawaited(server.close());
      final registration = _deviceLinkMdnsRegistration;
      _deviceLinkMdnsRegistration = null;
      if (registration != null) {
        unawaited(_unregisterDeviceLinkMdnsRegistration(registration));
      }
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

    await _connectSshTab(newTab, host, identity, onHostKeyPrompt);
  }

  /// Opens an SSH shell on [tab] against [host] and wires the resulting
  /// session into the tab's terminal and bridge.
  ///
  /// Shared by [openTabForHost] and by `splitTab` so that splitting an SSH
  /// host session opens a second SSH session to the same host (and keeps
  /// splits working on mobile, where a local PTY is not available).
  Future<void> _connectSshTab(
    TerminalTabSession tab,
    HostModel host,
    IdentityModel? identity,
    HostKeyPromptCallback? onHostKeyPrompt,
  ) async {
    final terminal = tab.terminal;
    // A reconnect reuses the emulator, so it starts from whatever the dead
    // session left latched. See [_resetTerminalForNewSession].
    _resetTerminalForNewSession(terminal);
    try {
      // ProxyJump: connect each hop in turn, tunneling every subsequent hop's
      // transport through the previous hop's already-authenticated client.
      //
      // Gated on the synchronous `jumpHostId` check, not just an empty
      // resolved chain: `await` always inserts a microtask gap even for an
      // already-completed Future, so unconditionally awaiting
      // `_resolveJumpChain` would delay `tab.sshSessionManager` being set
      // below past the caller's next synchronous read of it — every hostless
      // connect, not just jump ones.
      SSHClient? viaClient;
      if (host.jumpHostId != null) {
        final jumpChain = await _resolveJumpChain(host);
        for (final jumpHost in jumpChain) {
          final jumpIdentity = jumpHost.identityId == null
              ? null
              : await ref
                    .read(vaultRepositoryProvider)
                    .getIdentityById(jumpHost.identityId!);
          final jumpManager = SSHSessionManager(
            knownHostsDao: ref.read(knownHostsDaoProvider),
          );
          tab.jumpSessionManagers.add(jumpManager);
          final jumpConfig = _buildConnectConfig(
            jumpHost,
            jumpIdentity,
            onHostKeyPrompt: onHostKeyPrompt,
          );
          terminal.write(
            '\x1b[1;34m[SSH]\x1b[0m Connecting via jump host \x1b[1;36m'
            '${jumpConfig.username}@${jumpConfig.hostname}:${jumpConfig.port}'
            '\x1b[0m...\r\n',
          );
          viaClient = await jumpManager.connect(
            jumpConfig,
            viaClient: viaClient,
          );
        }
      }

      final sessionManager = SSHSessionManager(
        knownHostsDao: ref.read(knownHostsDaoProvider),
      );
      tab.sshSessionManager = sessionManager;

      final config = _buildConnectConfig(
        host,
        identity,
        onHostKeyPrompt: onHostKeyPrompt,
      );

      terminal.write(
        '\x1b[1;34m[SSH]\x1b[0m Connecting to \x1b[1;36m'
        '${config.username}@${config.hostname}:${config.port}\x1b[0m...\r\n',
      );

      await sessionManager.connect(config, viaClient: viaClient);
      try {
        // Mosh only changes *how* the shell is opened: the SSH connect, host
        // key verification, and identity resolution above are shared, and the
        // client stays live underneath either way.
        final startedMosh = host.protocol == 'mosh'
            ? await _startMoshShell(tab, host, config, sessionManager)
            : false;

        if (!startedMosh) {
          final sshSession = await sessionManager.openShell(
            width: terminal.viewWidth,
            height: terminal.viewHeight,
          );

          final bridge = TerminalSSHBridge(
            terminal: terminal,
            session: sshSession,
            onClosed: () => _handleRemoteExit(tab),
          );

          tab.sshBridge = bridge;
          // A dropped SSH keep-alive means a dead tab here. On a Mosh tab it
          // means nothing — surviving exactly that is the point — so the
          // listener is deliberately not wired in that branch.
          tab.sshClientChangesSub = sessionManager.clientChanges.listen(
            (client) => _handleClientChange(tab, client),
          );
          // The view has already sized the terminal by now, so `onResize` —
          // only wired when the bridge is built — never fires for that first
          // layout and the remote PTY would stay at whatever openShell
          // requested.
          bridge.resizeTerminal(terminal.viewWidth, terminal.viewHeight);
        }

        tab.isConnecting = false;
        tab.isConnected = true;
        tab.disconnectCause = null;

        state = state.copyWith(tabs: [...state.tabs]);
        // Wire broadcast if this pane is already part of the selection.
        _syncBroadcast();
      } catch (e) {
        // A failure after a successful connect (e.g. server refuses a PTY)
        // must tear the client down; otherwise the socket and keep-alive
        // timer keep running against a dead tab.
        await sessionManager.close();
        rethrow;
      }
    } catch (e) {
      tab.isConnecting = false;
      tab.isConnected = false;
      tab.errorMessage = e.toString();
      terminal.write(
        '\r\n\x1b[1;31m[Connection Error]\x1b[0m Failed to connect: $e\r\n',
      );
      state = state.copyWith(tabs: [...state.tabs]);
      // Not nulled: the error banner/reconnect path expects a failed tab to
      // still carry a (now-closed) session manager, and the next connect
      // attempt (see `tab.sshSessionManager = sessionManager` above) always
      // overwrites this with a fresh one anyway.
      await tab.sshSessionManager?.close();
      await tab.moshLinkSub?.cancel();
      tab.moshLinkSub = null;
      await tab.moshSessionManager?.close();
      tab.moshSessionManager = null;
      for (final jumpManager in tab.jumpSessionManagers.reversed) {
        await jumpManager.close();
      }
      tab.jumpSessionManagers = [];
    }
  }

  /// Starts a Mosh shell on [tab] over the already-authenticated
  /// [sessionManager], returning false when the caller should open a plain SSH
  /// shell instead.
  ///
  /// Every failure here is recoverable: the SSH client is connected and idle,
  /// so a host without `mosh-server` — the common case — lands the user in a
  /// working shell with one line of explanation rather than on an error screen.
  Future<bool> _startMoshShell(
    TerminalTabSession tab,
    HostModel host,
    SSHConnectConfig config,
    SSHSessionManager sessionManager,
  ) async {
    final terminal = tab.terminal;

    if (host.jumpHostId != null) {
      // UDP does not travel through an SSH channel, so there is no path for
      // the Mosh datagrams to take. Saying so beats a session that silently
      // never comes up.
      terminal.write(
        '\r\n\x1b[33m[Mosh]\x1b[0m Not available through a jump host '
        '(UDP cannot be tunneled). Using SSH.\r\n',
      );
      return false;
    }

    final client = sessionManager.client;
    if (client == null) return false;

    final manager = MoshSessionManager();
    tab.moshSessionManager = manager;

    try {
      final address = await _resolveMoshAddress(config.hostname);

      terminal.write(
        '\x1b[1;34m[Mosh]\x1b[0m Starting mosh-server on \x1b[1;36m'
        '${config.hostname}\x1b[0m...\r\n',
      );

      final transport = await manager.connect(
        client: client,
        address: address,
        bootstrap: _buildMoshBootstrap(host),
        columns: terminal.viewWidth,
        rows: terminal.viewHeight,
      );

      final bridge = TerminalMoshBridge(
        terminal: terminal,
        session: transport,
        predictionEngine: tab.moshPredictionEngine,
        onPredictionChanged: tab.refreshMoshPredictionText,
        onClosed: () => _handleRemoteExit(tab),
      );
      tab.moshBridge = bridge;
      // Same first-layout gap as the SSH branch: the view sized the terminal
      // before `onResize` existed.
      bridge.resizeTerminal(terminal.viewWidth, terminal.viewHeight);

      tab.moshLinkSub = manager.linkStates.listen(
        (linkState) => _handleMoshLinkState(tab, linkState),
      );
      _watchConnectivity();
      return true;
    } catch (e) {
      terminal.write(
        '\r\n\x1b[33m[Mosh]\x1b[0m $e\r\n'
        '\x1b[33m[Mosh]\x1b[0m Falling back to SSH.\r\n',
      );
      await manager.close();
      tab.moshSessionManager = null;
      return false;
    }
  }

  /// Builds the `mosh-server` command from the host's own settings, falling
  /// back to the mosh defaults for anything left blank.
  ///
  /// The port range is re-checked here rather than trusted: the form validates
  /// it, but a row can also arrive from an import or an older write, and
  /// `MoshSshBootstrap` throws on a range it cannot use — which would turn a
  /// bad stored value into a failed connect instead of a default one.
  MoshSshBootstrap _buildMoshBootstrap(HostModel host) {
    const defaults = MoshSshBootstrap();
    final binary = host.moshServerPath?.trim();
    final range = host.moshPortRange?.trim().split(':') ?? const [];
    final start = range.length == 2 ? int.tryParse(range[0].trim()) : null;
    final end = range.length == 2 ? int.tryParse(range[1].trim()) : null;
    final usable =
        start != null &&
        end != null &&
        start >= 1 &&
        end <= 65535 &&
        end >= start;

    return MoshSshBootstrap(
      serverBinary: (binary == null || binary.isEmpty)
          ? defaults.serverBinary
          : binary,
      serverPort: usable ? start : defaults.serverPort,
      serverPortEnd: usable ? end : defaults.serverPortEnd,
    );
  }

  /// Resolves the address the Mosh datagrams are sent to.
  ///
  /// An IP literal — what most saved hosts are — is used as-is, with no lookup
  /// at all. A name is resolved once, here, and the result is handed to the
  /// session manager so nothing downstream can resolve it a second time.
  ///
  /// The residual case is round-robin DNS, where this lookup can land on a
  /// different machine than the SSH connection did. `mosh-server` binds to the
  /// address SSH arrived on, so the mismatch shows up as a session that never
  /// answers rather than as a shell on the wrong host, and the connect fails
  /// into the SSH fallback above. Reading the address off the SSH socket would
  /// close the gap, but dartssh2 does not expose it.
  Future<InternetAddress> _resolveMoshAddress(String hostname) async {
    final literal = InternetAddress.tryParse(hostname);
    if (literal != null) return literal;

    final addresses = await InternetAddress.lookup(hostname);
    if (addresses.isEmpty) {
      throw MoshBootstrapException('Could not resolve $hostname.');
    }
    return addresses.first;
  }

  /// Records a Mosh link update so the tab can show it.
  ///
  /// Nothing here changes the connection state. A stale link is a working
  /// session that has been quiet, and the end of a session arrives through the
  /// bridge's `onClosed` like any other.
  void _handleMoshLinkState(TerminalTabSession tab, MoshLinkState linkState) {
    if (!state.tabs.any((t) => t.id == tab.id)) return;
    tab.moshLinkState = linkState;
    state = state.copyWith(tabs: [...state.tabs]);
  }

  /// Walks `jumpHostId` outward from [target], returning the hops in
  /// connection order: the directly-reachable outermost host first, the jump
  /// nearest [target] last. Empty when [target] has no `ProxyJump`.
  ///
  /// Throws on a missing host, a cycle, or an unreasonably long chain rather
  /// than looping forever or connecting through a broken link silently.
  Future<List<HostModel>> _resolveJumpChain(HostModel target) async {
    const maxHops = 8;
    final repo = ref.read(hostsRepositoryProvider);
    final chain = <HostModel>[];
    final visited = <String>{target.id};
    var nextId = target.jumpHostId;
    while (nextId != null) {
      if (!visited.add(nextId)) {
        throw StateError(
          'ProxyJump chain for "${target.label}" contains a cycle.',
        );
      }
      if (chain.length >= maxHops) {
        throw StateError(
          'ProxyJump chain for "${target.label}" exceeds $maxHops hops.',
        );
      }
      final jumpHost = await repo.getHostById(nextId);
      if (jumpHost == null) {
        throw StateError(
          'Jump host referenced by "${target.label}" no longer exists.',
        );
      }
      chain.add(jumpHost);
      nextId = jumpHost.jumpHostId;
    }
    return chain.reversed.toList();
  }

  /// Builds the connect config for one hop (a jump host or the final
  /// target): resolves the effective username from, in order, the host's own
  /// `username` field, a `user@host` prefix embedded in the hostname, the
  /// identity's username, and finally the local OS user — matching the
  /// fallback order `ssh` itself uses rather than silently trying `root`.
  SSHConnectConfig _buildConnectConfig(
    HostModel host,
    IdentityModel? identity, {
    HostKeyPromptCallback? onHostKeyPrompt,
  }) {
    String cleanHostname = host.hostname.trim();
    String? parsedUser;
    if (cleanHostname.contains('@')) {
      final atIndex = cleanHostname.indexOf('@');
      parsedUser = cleanHostname.substring(0, atIndex).trim();
      cleanHostname = cleanHostname.substring(atIndex + 1).trim();
    }

    final hostUser = host.username?.trim();
    final identityUser = identity?.username.trim();
    final osUser =
        Platform.environment['USER'] ?? Platform.environment['USERNAME'];
    final effectiveUsername = (hostUser != null && hostUser.isNotEmpty)
        ? hostUser
        : ((parsedUser != null && parsedUser.isNotEmpty)
              ? parsedUser
              : ((identityUser != null && identityUser.isNotEmpty)
                    ? identityUser
                    : (osUser ?? '')));

    return SSHConnectConfig(
      hostname: cleanHostname,
      port: host.port,
      username: effectiveUsername,
      password: identity?.password,
      privateKeyPem: identity?.privateKey,
      passphrase: identity?.passphrase,
      onHostKeyPrompt: onHostKeyPrompt,
    );
  }

  /// Re-establishes the SSH session of a tab whose connection dropped or
  /// failed, re-reading the host so any edit made since the tab was opened
  /// applies, and reusing the stored host key prompt callback. The old bridge
  /// and manager are torn down first so a single live session per tab is
  /// preserved.
  Future<void> reconnectTab(String tabId) async {
    final index = state.tabs.indexWhere((t) => t.id == tabId);
    if (index == -1) return;
    final tab = state.tabs[index];
    if (tab.sessionType != TerminalSessionType.ssh) return;
    if (tab.host == null) return;
    if (tab.isConnecting) return;

    // Flip the tab state before anything awaits: the old manager's `close()`
    // null emission is then ignored by the drop listener, the UI shows the
    // reconnect in flight straight away, and the guard above rejects a second
    // reconnect for this tab.
    tab.isConnected = false;
    tab.isConnecting = true;
    tab.errorMessage = null;
    tab.disconnectCause = null;
    state = state.copyWith(tabs: [...state.tabs]);

    await _refreshTabHost(tab);
    final host = tab.host!;

    await tab.sshClientChangesSub?.cancel();
    tab.sshClientChangesSub = null;
    await tab.moshLinkSub?.cancel();
    tab.moshLinkSub = null;
    tab.moshLinkState = null;
    if (tab.sshBridge != null) {
      await tab.sshBridge!.dispose(closeSession: true);
      tab.sshBridge = null;
    }
    // A Mosh session cannot be reattached — the client holds the OCB counter
    // state and the server's replay filter rejects an old sequence — so a
    // reconnect always starts a fresh one.
    if (tab.moshBridge != null) {
      await tab.moshBridge!.dispose(closeSession: true);
      tab.moshBridge = null;
    }
    if (tab.moshSessionManager != null) {
      await tab.moshSessionManager!.close();
      tab.moshSessionManager = null;
    }
    if (tab.sshSessionManager != null) {
      await tab.sshSessionManager!.close();
      tab.sshSessionManager = null;
    }
    for (final jumpManager in tab.jumpSessionManagers.reversed) {
      await jumpManager.close();
    }
    tab.jumpSessionManagers = [];

    await _connectSshTab(tab, host, tab.identity, tab.hostKeyPromptCallback);
  }

  /// Returns [terminal] to a state a fresh shell can be typed into.
  ///
  /// A full-screen program that dies with its transport — htop when the link
  /// drops — never gets to send the sequences that undo what it turned on, so
  /// mouse reporting, bracketed paste, application cursor keys and the
  /// alternate screen stay latched in the emulator. The reconnected shell then
  /// answers a scroll with `\x1b[<65;62;41M`, which it has no idea how to read
  /// and echoes back as `65;62;41M` across the prompt.
  ///
  /// A soft reset (DECSTR) drops exactly those modes and leaves the scrollback
  /// alone, so the session history above the reconnect survives.
  void _resetTerminalForNewSession(Terminal terminal) {
    if (terminal.isUsingAltBuffer) terminal.useMainBuffer();
    terminal.softReset();
  }

  /// Re-reads [tab]'s host row, and its identity when the host now points at a
  /// different one, so a reconnect uses the current settings.
  ///
  /// A tab holds the host it was opened with. Without this, editing a host and
  /// reconnecting an open tab silently keeps connecting with the old values —
  /// switching a host to Mosh and reconnecting would come up on SSH with no
  /// explanation.
  ///
  /// Best-effort by design: the tab's own copy is a valid connection target on
  /// its own, so a host that has since been deleted, or an identity that cannot
  /// be decrypted right now, leaves the reconnect to proceed with what the tab
  /// already holds instead of refusing to reconnect at all.
  Future<void> _refreshTabHost(TerminalTabSession tab) async {
    final hostId = tab.host?.id;
    if (hostId == null) return;

    final HostModel? fresh;
    try {
      fresh = await ref.read(hostsRepositoryProvider).getHostById(hostId);
    } catch (_) {
      return;
    }
    if (fresh == null) return;

    if (fresh.identityId != tab.identity?.id) {
      try {
        tab.identity = fresh.identityId == null
            ? null
            : await ref
                  .read(identitiesProvider.notifier)
                  .getDecryptedIdentity(fresh.identityId!);
      } catch (_) {
        // Leave the previous credentials in place; a locked vault surfaces as
        // an authentication failure from the connect itself, which says more
        // than anything this could report.
      }
    }
    tab.host = fresh;
  }

  /// Reacts to [SSHSessionManager.clientChanges]: a `null` client means the
  /// session was closed, either by the local manager (reconnect teardown,
  /// tab close) or by a dropped keep-alive connection. Only the drop case
  /// needs the UI flipped to disconnected; the tab must still be live in
  /// the state (the manager also emits null during [closeTab] teardown).
  void _handleClientChange(TerminalTabSession tab, SSHClient? client) {
    if (client != null) return;
    if (!tab.isConnected) return;
    if (!state.tabs.any((t) => t.id == tab.id)) return;
    _markTabDisconnected(tab, TerminalDisconnectCause.connectionLost);
  }

  /// Reacts to the bridge's remote streams ending: the shell on the other side
  /// exited. That is an ordinary end to a session, so it is recorded as such
  /// and not reported as a failure — the bridge has already written its own
  /// `[Session closed / Process exited]` notice to the buffer.
  void _handleRemoteExit(TerminalTabSession tab) {
    if (!tab.isConnected) return;
    if (!state.tabs.any((t) => t.id == tab.id)) return;
    _markTabDisconnected(tab, TerminalDisconnectCause.remoteExit);
  }

  /// Flips [tab] to the disconnected state, detaches its bridge, and records
  /// [cause] so the view can offer a reconnect with the right tone. Only a
  /// dropped transport is announced in the terminal buffer; a remote exit was
  /// already announced by the bridge.
  void _markTabDisconnected(
    TerminalTabSession tab,
    TerminalDisconnectCause cause,
  ) {
    tab.isConnected = false;
    tab.isConnecting = false;
    tab.disconnectCause = cause;
    unawaited(tab.sshBridge?.dispose(closeSession: true) ?? Future.value());
    tab.sshBridge = null;
    unawaited(tab.moshBridge?.dispose(closeSession: true) ?? Future.value());
    tab.moshBridge = null;
    tab.moshLinkState = null;
    if (cause == TerminalDisconnectCause.connectionLost) {
      tab.terminal.write('\r\n\x1b[1;31m[Connection lost]\x1b[0m\r\n');
    }
    state = state.copyWith(tabs: [...state.tabs]);
  }

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

  /// Starts the shell behind [tab] and wires it up once it exists.
  Future<void> _attachLocalShell(TerminalTabSession tab) async {
    final terminal = tab.terminal;
    try {
      final manager = ref.read(localPtyManagerProvider);
      final bridge = await manager.startAndBridge(
        terminal,
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
      newActiveId = _focusAfterClose(
        closedTab: state.tabs[index],
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

  /// Looks a pane up in an arbitrary list, which the close paths need on the
  /// pre-close snapshot rather than on [state].
  TerminalTabSession? _findInList(List<TerminalTabSession> tabs, String id) {
    for (final tab in tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  /// Walks [tabs] up the split tree and returns the id of [tab]'s root pane —
  /// the tab it is displayed in. The loop is bounded by the list length so a
  /// corrupted parent link cannot spin forever.
  String _rootIdOf(TerminalTabSession tab, List<TerminalTabSession> tabs) {
    var current = tab;
    for (var hops = 0; hops < tabs.length; hops++) {
      final parentId = current.splitParentId;
      if (parentId == null) return current.id;
      final parent = _findInList(tabs, parentId);
      if (parent == null) return current.id;
      current = parent;
    }
    return current.id;
  }

  /// Picks the pane that takes focus once [closedTab] and its subtree are gone.
  ///
  /// Focus must not leave the tab the user was working in: closing one pane of
  /// a split hands focus to another pane of the *same* root tab, and only a tab
  /// that disappears entirely moves focus to a neighbouring tab. Both searches
  /// run in root order rather than by flat index into [state.tabs], where split
  /// panes are appended after every other tab — indexing there lands on an
  /// unrelated tab's pane and silently switches tabs under the user.
  String? _focusAfterClose({
    required TerminalTabSession closedTab,
    required List<TerminalTabSession> remainingTabs,
  }) {
    if (remainingTabs.isEmpty) return null;

    final oldTabs = state.tabs;
    final rootId = _rootIdOf(closedTab, oldTabs);

    // The closed pane's tab survives: stay inside it. The nearest surviving
    // ancestor is the pane that grows into the freed space, so it gets focus;
    // failing that, any surviving pane of the tab beats leaving the tab.
    final survivorsInTab = remainingTabs
        .where((t) => _rootIdOf(t, oldTabs) == rootId)
        .toList();
    if (survivorsInTab.isNotEmpty) {
      final survivingIds = survivorsInTab.map((t) => t.id).toSet();
      var ancestorId = closedTab.splitParentId;
      for (var hops = 0; hops < oldTabs.length && ancestorId != null; hops++) {
        if (survivingIds.contains(ancestorId)) return ancestorId;
        ancestorId = _findInList(oldTabs, ancestorId)?.splitParentId;
      }
      return survivorsInTab.first.id;
    }

    // The whole tab went away: fall back to the neighbouring tab, counted
    // among root panes only.
    final oldRootIds = oldTabs
        .where((t) => t.splitParentId == null)
        .map((t) => t.id)
        .toList();
    final remainingRoots = remainingTabs
        .where((t) => t.splitParentId == null)
        .toList();
    if (remainingRoots.isEmpty) return remainingTabs.first.id;

    final closedRootIndex = oldRootIds.indexOf(rootId);
    final newIndex =
        closedRootIndex < 0 || closedRootIndex >= remainingRoots.length
        ? remainingRoots.length - 1
        : closedRootIndex;
    return remainingRoots[newIndex].id;
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

    final heir = children.last;
    heir.splitParentId = pane.splitParentId;
    heir.splitDirection = pane.splitDirection;
    heir.splitRatio = pane.splitRatio;
    for (final child in children) {
      if (identical(child, heir)) continue;
      child.splitParentId = heir.id;
    }

    // The fold that lays panes out reads sibling order off this list, so the
    // heir has to inherit the closed pane's position in it, not keep its own.
    final remainingTabs = <TerminalTabSession>[];
    for (final tab in state.tabs) {
      if (tab.id == paneId) {
        remainingTabs.add(heir);
        continue;
      }
      if (identical(tab, heir)) continue;
      remainingTabs.add(tab);
    }

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

  Stream<void> get deviceLinkPairingEvents => _deviceLinkPairingEvents.stream;

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
  /// short-lived QR payload used by the first pairing flow. The server stays
  /// alive after the QR screen closes so the newly paired connection can keep
  /// using the same listener.
  Future<DeviceLinkQrPayload> createDeviceLinkPairingPayload() async {
    final server = await _ensureDeviceLinkServer();
    final registeredName = _deviceLinkMdnsRegistration?.service.name;
    final mdnsName = registeredName == null
        ? null
        : '$registeredName.$deviceLinkMdnsServiceType.local';
    return server.createPairingPayload(mdnsName: mdnsName);
  }

  /// Ensures the desktop listener exists when a previous QR pairing is
  /// already persisted. A clean install must not open a LAN listener merely
  /// because the app was launched.
  Future<void> ensureDeviceLinkServerForPairedDevices() async {
    if (!supportsLocalShell) return;
    if (!_isVaultAvailable) return;
    final pairingRepository = ref.read(deviceLinkPairingRepositoryProvider);
    if ((await pairingRepository.getAll()).isEmpty) return;
    if (!_isVaultAvailable) return;
    await _ensureDeviceLinkServer();
  }

  /// Stops the Device Link listener, all authenticated connections, and its
  /// mDNS advertisement. The lifecycle generation also cancels a startup that
  /// is still loading the identity or registering mDNS, preventing an orphan
  /// server/registration from being published after the vault is locked.
  Future<void> stopDeviceLinkServer() {
    final existingStop = _deviceLinkServerStop;
    if (existingStop != null) return existingStop;

    ++_deviceLinkLifecycleGeneration;
    final startup = _deviceLinkServerStartup;
    final server = _deviceLinkServer;
    _deviceLinkServer = null;
    final registration = _deviceLinkMdnsRegistration;
    _deviceLinkMdnsRegistration = null;

    final stop = () async {
      // Let an in-flight start observe the new generation before closing any
      // server instance it may have created.
      try {
        await startup;
      } on Object catch (_) {}

      await server?.close();
      if (registration != null) {
        await _unregisterDeviceLinkMdnsRegistration(registration);
      }
    }();

    late final Future<void> trackedStop;
    trackedStop = stop.whenComplete(() {
      if (identical(_deviceLinkServerStop, trackedStop)) {
        _deviceLinkServerStop = null;
      }
    });
    _deviceLinkServerStop = trackedStop;
    return trackedStop;
  }

  @visibleForTesting
  bool get isDeviceLinkServerRunning => _deviceLinkServer?.isRunning ?? false;

  @visibleForTesting
  bool get deviceLinkVaultAvailable => _isVaultAvailable;

  Future<DeviceLinkServer> _ensureDeviceLinkServer() async {
    if (!_isVaultAvailable) {
      throw StateError('Device Link is unavailable while the vault is locked');
    }

    final stop = _deviceLinkServerStop;
    if (stop != null) await stop;
    if (_deviceLinkDisposed || !_isVaultAvailable) {
      throw StateError('Device Link startup cancelled');
    }

    final existing = _deviceLinkServer;
    if (existing != null && existing.isRunning) return Future.value(existing);

    final inFlight = _deviceLinkServerStartup;
    if (inFlight != null) return inFlight;

    final startup = _startDeviceLinkServer(_deviceLinkLifecycleGeneration);
    late final Future<DeviceLinkServer> trackedStartup;
    trackedStartup = startup.whenComplete(() {
      if (identical(_deviceLinkServerStartup, trackedStartup)) {
        _deviceLinkServerStartup = null;
      }
    });
    _deviceLinkServerStartup = trackedStartup;
    return trackedStartup;
  }

  Future<DeviceLinkServer> _startDeviceLinkServer(int generation) async {
    var server = _deviceLinkServer;
    if (server == null) {
      final pairingRepository = ref.read(deviceLinkPairingRepositoryProvider);
      final identity = await _loadDeviceLinkIdentity();
      if (_deviceLinkDisposed || generation != _deviceLinkLifecycleGeneration) {
        throw StateError('Device Link notifier disposed during startup');
      }
      server = DeviceLinkServer(
        identity: identity,
        hostName: Platform.localHostname.isEmpty
            ? 'shellvibe-desktop'
            : Platform.localHostname,
        appVersion: AppConstants.appVersion,
        sessionTransportsProvider: deviceLinkSessionTransports,
        pairedDeviceAuthenticator: pairingRepository.authenticate,
        pairedDevicePersister: (record) => pairingRepository.savePairedDevice(
          id: record.id,
          name: record.name,
          platform: record.platform,
          secret: record.secret,
          publicKey: record.publicKey,
          pairedAt: record.pairedAt,
        ),
        // Only reached for an id the phone authenticated as its own, so this
        // deletes the row the same phone left behind under an older identity.
        pairedDeviceRemover: pairingRepository.remove,
        onPairingCompleted: () {
          if (!_deviceLinkPairingEvents.isClosed) {
            _deviceLinkPairingEvents.add(null);
          }
        },
      );
      await server.start();
      if (_deviceLinkDisposed || generation != _deviceLinkLifecycleGeneration) {
        await server.close();
        throw StateError('Device Link notifier disposed during startup');
      }
      _deviceLinkServer = server;
    } else if (!server.isRunning) {
      await server.start();
      if (_deviceLinkDisposed || generation != _deviceLinkLifecycleGeneration) {
        await server.close();
        throw StateError('Device Link startup cancelled');
      }
    }

    await _ensureDeviceLinkMdnsRegistration(server, generation);
    if (_deviceLinkDisposed || generation != _deviceLinkLifecycleGeneration) {
      if (identical(_deviceLinkServer, server)) _deviceLinkServer = null;
      await server.close();
      throw StateError('Device Link startup cancelled');
    }
    return server;
  }

  Future<void> _ensureDeviceLinkMdnsRegistration(
    DeviceLinkServer server,
    int generation,
  ) async {
    if (_deviceLinkMdnsRegistration != null) return;
    final discovery = DeviceDiscovery();
    if (!discovery.supportsMdns) return;
    try {
      final registration = await discovery.register(
        name: server.hostName,
        port: server.port,
      );
      if (_deviceLinkDisposed || generation != _deviceLinkLifecycleGeneration) {
        await _unregisterDeviceLinkMdnsRegistration(
          registration,
          discovery: discovery,
        );
        return;
      }
      _deviceLinkMdnsRegistration = registration;
    } on Object catch (error) {
      // Direct QR addresses remain valid when mDNS is unavailable (Linux,
      // missing permission, or an isolated Wi-Fi network).
      debugPrint('[Device Link] mDNS registration unavailable: $error');
    }
  }

  Future<void> _unregisterDeviceLinkMdnsRegistration(
    nsd.Registration registration, {
    DeviceDiscovery? discovery,
  }) async {
    try {
      await (discovery ?? DeviceDiscovery()).unregister(registration);
    } on Object catch (error) {
      debugPrint('[Device Link] mDNS unregistration unavailable: $error');
    }
  }

  Future<DeviceLinkIdentity> _loadDeviceLinkIdentity() async {
    final storage = ref.read(secureStorageServiceProvider);
    final stored = await storage.getToken(
      SecureStorageKeys.deviceLinkServerIdentity,
    );
    if (stored != null) {
      try {
        final object = jsonDecode(stored);
        if (object is Map<String, dynamic> &&
            object['certificatePem'] is String &&
            object['privateKeyPem'] is String) {
          return DeviceLinkIdentity.fromPem(
            certificatePem: object['certificatePem'] as String,
            privateKeyPem: object['privateKeyPem'] as String,
          );
        }
      } catch (_) {
        await storage.deleteToken(SecureStorageKeys.deviceLinkServerIdentity);
      }
    }

    final identity = DeviceLinkIdentity.generate();
    await storage.saveToken(
      SecureStorageKeys.deviceLinkServerIdentity,
      jsonEncode({
        'certificatePem': identity.certificatePem,
        'privateKeyPem': identity.privateKeyPem,
      }),
    );
    return identity;
  }

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

  /// Exchanges the positions of two panes of the same tab.
  ///
  /// This is a swap of what each slot *shows*, not a rearrangement of the
  /// layout: the split directions, the ratios and the nesting all stay exactly
  /// where they are, and only the two sessions trade places. So the children of
  /// each pane stay with the slot rather than travelling with their parent,
  /// which is why they are re-pointed at the other pane before the two slot
  /// descriptions (parent, direction, ratio) are exchanged.
  ///
  /// Keeping the shape of the tree fixed is also what makes this always safe.
  /// Swapping only the parent links would relabel edges the rest of the tree
  /// still points at, and for an ancestor and a descendant two levels apart
  /// that closes a cycle (`a -> b -> a`) and the layout fold never terminates.
  /// Permuting two positions of an unchanged tree cannot.
  ///
  /// Panes of different tabs are refused: only one tab is on screen, so such a
  /// drop cannot be aimed, and it would move a pane out from under the
  /// selection and focus state of the tab it was in.
  void swapPanes(String paneId, String otherPaneId) {
    if (paneId == otherPaneId) return;

    final index = state.tabs.indexWhere((t) => t.id == paneId);
    final otherIndex = state.tabs.indexWhere((t) => t.id == otherPaneId);
    if (index == -1 || otherIndex == -1) return;

    final pane = state.tabs[index];
    final other = state.tabs[otherIndex];
    if (_rootIdOf(pane, state.tabs) != _rootIdOf(other, state.tabs)) return;

    for (final tab in state.tabs) {
      if (tab.id == paneId || tab.id == otherPaneId) continue;
      if (tab.splitParentId == paneId) {
        tab.splitParentId = otherPaneId;
      } else if (tab.splitParentId == otherPaneId) {
        tab.splitParentId = paneId;
      }
    }

    final paneParentId = pane.splitParentId;
    final paneDirection = pane.splitDirection;
    final paneRatio = pane.splitRatio;

    // When one pane is the other's parent, the slot it is moving into hangs off
    // the slot it is vacating — which the other pane now holds.
    pane.splitParentId = other.splitParentId == paneId
        ? otherPaneId
        : other.splitParentId;
    pane.splitDirection = other.splitDirection;
    pane.splitRatio = other.splitRatio;

    other.splitParentId = paneParentId == otherPaneId ? paneId : paneParentId;
    other.splitDirection = paneDirection;
    other.splitRatio = paneRatio;

    // Sibling order is read off this list by the layout fold, so the two panes
    // have to take each other's place here as well. Leaving the order alone
    // would move a pane into a slot and then lay it out on the wrong side of
    // the sibling it shares that slot's container with.
    final reordered = [...state.tabs];
    reordered[index] = other;
    reordered[otherIndex] = pane;

    state = state.copyWith(tabs: reordered);
  }

  /// Moves [paneId] out of its slot and splits [targetId] with it, along
  /// [edge].
  ///
  /// The pane travels alone. Its own children stay behind and are promoted into
  /// the slot it vacates, exactly as [closePane] promotes them — a pane's
  /// children describe how its rectangle is subdivided, so they belong to the
  /// slot rather than to the pane that happens to sit in it.
  ///
  /// A pane always joins its parent's split on the trailing side (the fold that
  /// lays panes out puts the newest child there), so docking to the left or the
  /// top is the trailing case followed by a swap: the arriving pane takes the
  /// target's slot and the target becomes the child. That leaves the same two
  /// rectangles with their occupants exchanged, which is what the leading edges
  /// mean, and it costs nothing in the model — no pane has to record which side
  /// of its split it is on.
  void movePaneTo(String paneId, String targetId, PaneDockEdge edge) {
    if (paneId == targetId) return;

    final pane = _findInList(state.tabs, paneId);
    final target = _findInList(state.tabs, targetId);
    if (pane == null || target == null) return;
    if (_rootIdOf(pane, state.tabs) != _rootIdOf(target, state.tabs)) return;

    var tabs = [...state.tabs];
    final children = tabs.where((t) => t.splitParentId == paneId).toList();

    if (children.isEmpty) {
      tabs.removeWhere((t) => t.id == paneId);
    } else {
      // Same heir rule as closePane: the last child is the one laid out
      // directly against the departing pane, so it takes the vacated slot and
      // the earlier children hang off it, preserving their nesting and their
      // order on screen.
      final heir = children.last;
      heir.splitParentId = pane.splitParentId;
      heir.splitDirection = pane.splitDirection;
      heir.splitRatio = pane.splitRatio;
      for (final child in children) {
        if (identical(child, heir)) continue;
        child.splitParentId = heir.id;
      }
      final rebuilt = <TerminalTabSession>[];
      for (final tab in tabs) {
        if (tab.id == paneId) {
          rebuilt.add(heir);
          continue;
        }
        if (identical(tab, heir)) continue;
        rebuilt.add(tab);
      }
      tabs = rebuilt;
    }

    pane.splitParentId = targetId;
    pane.splitDirection = edge.axis;
    pane.splitRatio = 0.5;
    // Appended last so it is the innermost child of its new parent: it splits
    // the target's own rectangle rather than the target plus everything already
    // split off it.
    tabs.add(pane);

    state = state.copyWith(tabs: tabs);

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
      return _connectSshTab(
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
