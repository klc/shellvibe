import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm2/xterm.dart';

import '../../../../core/network/providers/network_providers.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/network/terminal_ssh_bridge.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../domain/models/terminal_tab_session.dart';
import '../../domain/services/broadcast_input_router.dart';

part 'terminal_tabs_notifier.g.dart';

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
    // Tees read the notifier's live selection, never a captured snapshot.
    _broadcastRouter.forwardCallback = _broadcastFrom;
    ref.onDispose(() {
      // Reading `state` is forbidden during life-cycles; restore tees from
      // the owned-tab set instead.
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
    final terminal = Terminal(maxLines: 10000);

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
      final sessionManager = SSHSessionManager(
        knownHostsDao: ref.read(knownHostsDaoProvider),
      );
      tab.sshSessionManager = sessionManager;

      String cleanHostname = host.hostname.trim();
      String? parsedUser;
      if (cleanHostname.contains('@')) {
        final atIndex = cleanHostname.indexOf('@');
        parsedUser = cleanHostname.substring(0, atIndex).trim();
        cleanHostname = cleanHostname.substring(atIndex + 1).trim();
      }

      final hostUser = host.username?.trim();
      final identityUser = identity?.username.trim();
      final effectiveUsername = (hostUser != null && hostUser.isNotEmpty)
          ? hostUser
          : ((parsedUser != null && parsedUser.isNotEmpty)
              ? parsedUser
              : ((identityUser != null && identityUser.isNotEmpty)
                  ? identityUser
                  : 'root'));

      final config = SSHConnectConfig(
        hostname: cleanHostname,
        port: host.port,
        username: effectiveUsername,
        password: identity?.password,
        privateKeyPem: identity?.privateKey,
        passphrase: identity?.passphrase,
        onHostKeyPrompt: onHostKeyPrompt,
      );

      terminal.write(
          '\x1b[1;34m[SSH]\x1b[0m Connecting to \x1b[1;36m$effectiveUsername@$cleanHostname:${host.port}\x1b[0m...\r\n');

      await sessionManager.connect(config);
      try {
        final sshSession = await sessionManager.openShell(
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        );

        final bridge = TerminalSSHBridge(
          terminal: terminal,
          session: sshSession,
          onClosed: () => _handleClientChange(tab, null),
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

        state = state.copyWith(tabs: [...state.tabs]);
        // Wire a broadcast tee if this pane is already part of the selection.
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
    }
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
    _markTabDisconnected(tab, 'Connection lost');
  }

  /// Flips [tab] to the disconnected state, detaches its bridge, and
  /// surfaces the reason in the terminal buffer so the view can offer a
  /// reconnect.
  void _markTabDisconnected(TerminalTabSession tab, String reason) {
    tab.isConnected = false;
    tab.isConnecting = false;
    tab.sshBridge?.dispose(closeSession: true);
    tab.sshBridge = null;
    tab.terminal.write('\r\n\x1b[1;31m[$reason]\x1b[0m\r\n');
    state = state.copyWith(tabs: [...state.tabs]);
  }

  void openLocalTab({String? title}) {
    final tabId = const Uuid().v4();
    final terminal = Terminal(maxLines: 10000);

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
    // Wire a broadcast tee if this pane is already part of the selection.
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

  /// Reconciles installed broadcast tees with the current selection.
  void _syncBroadcast() {
    _broadcastRouter.sync(
      selectedIds: state.selectedPaneIds,
      tabs: state.tabs,
    );
  }

  /// Forward handler invoked by installed tees with the origin pane id.
  /// Reads the live selection, so panes added or removed after a tee was
  /// installed are handled correctly.
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

  Future<void>? splitTab(
    String parentTabId, {
    Axis direction = Axis.horizontal,
    HostKeyPromptCallback? onHostKeyPrompt,
  }) {
    final parentIndex = state.tabs.indexWhere((t) => t.id == parentTabId);
    if (parentIndex == -1) return null;

    final parentTab = state.tabs[parentIndex];
    final splitId = const Uuid().v4();
    final terminal = Terminal(maxLines: 10000);

    // A split pane mirrors the session type of the pane it was created from.
    // Splitting an SSH host session opens a second SSH session to the same
    // host rather than a local shell; this also keeps splits working on
    // mobile, where a local PTY is not available.
    final isSshSplit = parentTab.sessionType == TerminalSessionType.ssh &&
        parentTab.host != null;

    final splitTab = TerminalTabSession(
      id: splitId,
      title: '${parentTab.title} (Split)',
      sessionType: isSshSplit
          ? TerminalSessionType.ssh
          : TerminalSessionType.local,
      host: parentTab.host,
      identity: parentTab.identity,
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
        parentTab.host!,
        parentTab.identity,
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
    // Wire a broadcast tee if this pane is already part of the selection.
    _syncBroadcast();
    return null;
  }
}
