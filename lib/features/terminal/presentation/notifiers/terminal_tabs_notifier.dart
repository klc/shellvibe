import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dart_mosh/dart_mosh.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm3/xterm.dart';

import '../../../../core/network/mosh_session_manager.dart';
import '../../../../core/network/providers/network_providers.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/network/terminal_mosh_bridge.dart';
import '../../../../core/network/terminal_ssh_bridge.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
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
  final BroadcastInputRouter _broadcastRouter = BroadcastInputRouter();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  TerminalTabsState build() {
    // Interceptors read the notifier's live selection, never a snapshot.
    _broadcastRouter.forwardCallback = _broadcastFrom;
    ref.onDispose(() {
      unawaited(_connectivitySub?.cancel() ?? Future.value());
      _connectivitySub = null;
      // Reading `state` is forbidden during life-cycles; drop interceptors
      // from the owned-tab set instead.
      _broadcastRouter.restoreAll(_ownedTabs.toList());
      for (final tab in _ownedTabs.toList()) {
        tab.dispose();
      }
      _ownedTabs.clear();
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
    state = state.copyWith(
      tabs: updatedTabs,
      activeTabId: tabId,
    );

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
              '\x1b[0m...\r\n');
          viaClient = await jumpManager.connect(jumpConfig, viaClient: viaClient);
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
          '${config.username}@${config.hostname}:${config.port}\x1b[0m...\r\n');

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
      terminal.write('\r\n\x1b[1;31m[Connection Error]\x1b[0m Failed to connect: $e\r\n');
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
    final osUser = Platform.environment['USER'] ??
        Platform.environment['USERNAME'];
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

    await _connectSshTab(
      tab,
      host,
      tab.identity,
      tab.hostKeyPromptCallback,
    );
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
    state = state.copyWith(
      tabs: updatedTabs,
      activeTabId: tabId,
    );

    try {
      final manager = ref.read(localPtyManagerProvider);
      final bridge = manager.startAndBridge(
        terminal,
        rows: terminal.viewHeight,
        columns: terminal.viewWidth,
      );

      newTab.ptyBridge = bridge;
      // See _connectSsh: the first layout resize happens before the bridge
      // wires `onResize`, so push the current size once by hand.
      bridge?.resizeTerminal(terminal.viewWidth, terminal.viewHeight);
      newTab.isConnecting = false;
      newTab.isConnected = bridge != null;
      if (bridge == null) {
        newTab.errorMessage = 'Failed to start local terminal session';
      }
    } catch (e) {
      newTab.isConnecting = false;
      newTab.isConnected = false;
      newTab.errorMessage = e.toString();
    }

    state = state.copyWith(tabs: [...state.tabs]);
    // Wire broadcast if this pane is already part of the selection.
    _syncBroadcast();
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
    final remainingTabs =
        state.tabs.where((t) => !closingIds.contains(t.id)).toList();
    String? newActiveId = state.activeTabId;

    if (closingIds.contains(state.activeTabId)) {
      if (remainingTabs.isNotEmpty) {
        final newIndex =
            index >= remainingTabs.length ? remainingTabs.length - 1 : index;
        newActiveId = remainingTabs[newIndex].id;
      } else {
        newActiveId = null;
      }
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
      await tab.dispose();
      _ownedTabs.remove(tab);
    }
  }

  void setActiveTab(String tabId) {
    if (state.tabs.any((t) => t.id == tabId)) {
      state = state.copyWith(activeTabId: tabId);
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
    _broadcastRouter.sync(
      selectedIds: state.selectedPaneIds,
      tabs: state.tabs,
    );
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
    if (!state.tabs.any((t) => t.id == tabId)) return;
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
    final isSshSplit = host != null ||
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

    try {
      final manager = ref.read(localPtyManagerProvider);
      final bridge = manager.startAndBridge(
        terminal,
        rows: terminal.viewHeight,
        columns: terminal.viewWidth,
      );
      splitTab.ptyBridge = bridge;
      bridge?.resizeTerminal(terminal.viewWidth, terminal.viewHeight);
      splitTab.isConnected = bridge != null;
      if (bridge == null) {
        splitTab.errorMessage = 'Failed to start local terminal session';
      }
    } catch (e) {
      splitTab.isConnected = false;
      splitTab.errorMessage = e.toString();
    }

    state = state.copyWith(
      tabs: [...state.tabs, splitTab],
      activeTabId: splitId,
    );
    // Wire broadcast if this pane is already part of the selection.
    _syncBroadcast();
    return null;
  }
}
