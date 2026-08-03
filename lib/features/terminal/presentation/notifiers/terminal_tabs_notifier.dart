import 'dart:async';

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

part 'terminal_tabs_notifier.g.dart';

class TerminalTabsState {
  final List<TerminalTabSession> tabs;
  final String? activeTabId;

  const TerminalTabsState({
    this.tabs = const [],
    this.activeTabId,
  });

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
  }) {
    return TerminalTabsState(
      tabs: tabs ?? this.tabs,
      activeTabId: clearActiveTabId ? null : (activeTabId ?? this.activeTabId),
    );
  }
}

@Riverpod(keepAlive: true)
class TerminalTabsNotifier extends _$TerminalTabsNotifier {
  final Set<TerminalTabSession> _ownedTabs = {};
  @override
  TerminalTabsState build() {
    ref.onDispose(() {
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
        );

        tab.sshBridge = bridge;
        // The view has already sized the terminal by now, so `onResize` — only
        // wired when the bridge is built — never fires for that first layout
        // and the remote PTY would stay at whatever openShell requested.
        bridge.resizeTerminal(terminal.viewWidth, terminal.viewHeight);
        tab.isConnecting = false;
        tab.isConnected = true;

        state = state.copyWith(tabs: [...state.tabs]);
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

    state = state.copyWith(
      tabs: remainingTabs,
      activeTabId: newActiveId,
      clearActiveTabId: newActiveId == null,
    );

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
    return null;
  }
}
