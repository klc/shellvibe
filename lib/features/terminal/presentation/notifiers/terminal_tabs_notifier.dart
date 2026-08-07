import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm3/xterm.dart';

import '../../../../core/network/providers/network_providers.dart';
import '../../../../core/network/ssh_session_manager.dart';
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

  @override
  TerminalTabsState build() {
    // Interceptors read the notifier's live selection, never a snapshot.
    _broadcastRouter.forwardCallback = _broadcastFrom;
    ref.onDispose(() {
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
        tab.sshClientChangesSub = sessionManager.clientChanges.listen(
          (client) => _handleClientChange(tab, client),
        );
        // The view has already sized the terminal by now, so `onResize` — only
        // wired when the bridge is built — never fires for that first layout
        // and the remote PTY would stay at whatever openShell requested.
        bridge.resizeTerminal(terminal.viewWidth, terminal.viewHeight);
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
      for (final jumpManager in tab.jumpSessionManagers.reversed) {
        await jumpManager.close();
      }
      tab.jumpSessionManagers = [];
    }
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
  /// failed, reusing the stored host, identity, and host key prompt
  /// callback. The old bridge and manager are torn down first so a single
  /// live session per tab is preserved.
  Future<void> reconnectTab(String tabId) async {
    final index = state.tabs.indexWhere((t) => t.id == tabId);
    if (index == -1) return;
    final tab = state.tabs[index];
    if (tab.sessionType != TerminalSessionType.ssh) return;
    final host = tab.host;
    if (host == null) return;
    if (tab.isConnecting) return;

    // Flip the tab state before tearing the old session down: the old
    // manager's `close()` null emission is then ignored by the drop
    // listener, and the UI shows the reconnect in flight.
    tab.isConnected = false;
    tab.isConnecting = true;
    tab.errorMessage = null;
    tab.disconnectCause = null;
    state = state.copyWith(tabs: [...state.tabs]);

    await tab.sshClientChangesSub?.cancel();
    tab.sshClientChangesSub = null;
    if (tab.sshBridge != null) {
      await tab.sshBridge!.dispose(closeSession: true);
      tab.sshBridge = null;
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
