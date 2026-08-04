import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm2/xterm.dart';

import '../../../../core/network/local_pty_manager.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/network/terminal_ssh_bridge.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../services/terminal_output_chain.dart';

enum TerminalSessionType { ssh, local }

/// Why a session that was connected is no longer live.
enum TerminalDisconnectCause {
  /// The remote shell exited (`exit`, `logout`, a killed process): an ordinary
  /// end to the session, not a failure.
  remoteExit,

  /// The transport went away underneath us — keep-alive failure, network drop,
  /// server-side kill.
  connectionLost,
}

/// Clamp range for a split pane's share of its split container.
const double kSplitPaneMinRatio = 0.15;
const double kSplitPaneMaxRatio = 0.85;

/// Model representing an active terminal tab session.
class TerminalTabSession {
  final String id;
  final String title;
  final TerminalSessionType sessionType;
  final HostModel? host;
  final IdentityModel? identity;
  final Terminal terminal;

  /// Shared owner of `terminal.onOutput`. Broadcast and the mobile extra-keys
  /// bar register interceptors here instead of wrapping the slot themselves,
  /// which is what lets them be added and removed independently and survive a
  /// bridge reconnect.
  late final TerminalOutputChain outputChain = TerminalOutputChain(terminal);

  SSHSessionManager? sshSessionManager;
  TerminalSSHBridge? sshBridge;

  /// Subscription to the session manager's client-change stream, used to
  /// detect a dropped keep-alive connection and flip the tab to
  /// disconnected. Replaced on every (re)connect, cancelled on tab close.
  StreamSubscription<SSHClient?>? sshClientChangesSub;

  /// Host key prompt callback captured at connect time so a reconnect re-runs
  /// host key verification through the same UI.
  HostKeyPromptCallback? hostKeyPromptCallback;

  TerminalLocalPtyBridge? ptyBridge;
  bool isConnecting;
  bool isConnected;
  String? errorMessage;

  /// Set when a live session ended by itself. `remoteExit` is a normal
  /// shell exit and must not be reported as an error; `connectionLost` is a
  /// dropped transport. Null while connecting or connected, and for a session
  /// that never came up (that case carries [errorMessage] instead).
  TerminalDisconnectCause? disconnectCause;

  final String? splitParentId;
  final Axis? splitDirection;

  /// Share (0..1) of the split container taken by this pane; the sibling takes 1 - share.
  double splitRatio = 0.5;

  TerminalTabSession({
    required this.id,
    required this.title,
    required this.sessionType,
    this.host,
    this.identity,
    required this.terminal,
    this.sshSessionManager,
    this.sshBridge,
    this.sshClientChangesSub,
    this.hostKeyPromptCallback,
    this.ptyBridge,
    this.isConnecting = false,
    this.isConnected = false,
    this.errorMessage,
    this.disconnectCause,
    this.splitParentId,
    this.splitDirection,
    this.splitRatio = 0.5,
  });

  /// Resizes the tab terminal and propagates dimensions to the active SSH or PTY session bridge.
  void resizeTerminal(int width, int height, [int pixelWidth = 0, int pixelHeight = 0]) {
    terminal.resize(width, height);
    sshBridge?.resizeTerminal(width, height, pixelWidth, pixelHeight);
    ptyBridge?.resizeTerminal(width, height);
  }

  Future<void> dispose() async {
    outputChain.dispose();
    await sshClientChangesSub?.cancel();
    sshClientChangesSub = null;
    if (sshBridge != null) {
      await sshBridge!.dispose(closeSession: true);
      sshBridge = null;
    }
    if (ptyBridge != null) {
      await ptyBridge!.dispose(killPty: true);
      ptyBridge = null;
    }
    if (sshSessionManager != null) {
      await sshSessionManager!.close();
      sshSessionManager = null;
    }
    // xterm2 guards write() against a disposed terminal, so late writes from
    // an in-flight connect do not crash after disposal.
    terminal.dispose();
  }
}
