import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';

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
  }) {
    return TerminalTabsState(
      tabs: tabs ?? this.tabs,
      activeTabId: activeTabId ?? this.activeTabId,
    );
  }
}

@riverpod
class TerminalTabsNotifier extends _$TerminalTabsNotifier {
  @override
  TerminalTabsState build() {
    ref.onDispose(() {
      for (final tab in state.tabs) {
        tab.dispose();
      }
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

    final updatedTabs = [...state.tabs, newTab];
    state = state.copyWith(
      tabs: updatedTabs,
      activeTabId: tabId,
    );

    try {
      final sessionManager = SSHSessionManager(
        knownHostsDao: ref.read(knownHostsDaoProvider),
      );
      newTab.sshSessionManager = sessionManager;

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
      final sshSession = await sessionManager.openShell();

      final bridge = TerminalSSHBridge(
        terminal: terminal,
        session: sshSession,
      );

      newTab.sshBridge = bridge;
      newTab.isConnecting = false;
      newTab.isConnected = true;

      state = state.copyWith(tabs: [...state.tabs]);
    } catch (e) {
      newTab.isConnecting = false;
      newTab.isConnected = false;
      newTab.errorMessage = e.toString();
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

    final manager = ref.read(localPtyManagerProvider);
    final bridge = manager.startAndBridge(terminal);

    newTab.ptyBridge = bridge;
    newTab.isConnecting = false;
    newTab.isConnected = bridge != null;

    state = state.copyWith(tabs: [...state.tabs]);
  }

  Future<void> closeTab(String tabId) async {
    final index = state.tabs.indexWhere((t) => t.id == tabId);
    if (index == -1) return;

    final targetTab = state.tabs[index];
    await targetTab.dispose();

    final remainingTabs = state.tabs.where((t) => t.id != tabId).toList();
    String? newActiveId = state.activeTabId;

    if (state.activeTabId == tabId) {
      if (remainingTabs.isNotEmpty) {
        final newIndex = index >= remainingTabs.length ? remainingTabs.length - 1 : index;
        newActiveId = remainingTabs[newIndex].id;
      } else {
        newActiveId = null;
      }
    }

    state = state.copyWith(
      tabs: remainingTabs,
      activeTabId: newActiveId,
    );
  }

  void setActiveTab(String tabId) {
    if (state.tabs.any((t) => t.id == tabId)) {
      state = state.copyWith(activeTabId: tabId);
    }
  }

  void splitTab(String parentTabId, {Axis direction = Axis.horizontal}) {
    final parentIndex = state.tabs.indexWhere((t) => t.id == parentTabId);
    if (parentIndex == -1) return;

    final parentTab = state.tabs[parentIndex];
    final splitId = const Uuid().v4();
    final terminal = Terminal(maxLines: 10000);

    final splitTab = TerminalTabSession(
      id: splitId,
      title: '${parentTab.title} (Split)',
      sessionType: TerminalSessionType.local,
      terminal: terminal,
      splitParentId: parentTabId,
      splitDirection: direction,
    );

    final manager = ref.read(localPtyManagerProvider);
    final bridge = manager.startAndBridge(terminal);
    splitTab.ptyBridge = bridge;
    splitTab.isConnected = bridge != null;

    state = state.copyWith(
      tabs: [...state.tabs, splitTab],
      activeTabId: splitId,
    );
  }
}
