import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm3/xterm.dart';

import '../../../../core/models/mosh_prediction_mode.dart';
import '../../../../core/network/local_pty_manager.dart';
import '../../../../core/network/mosh_prediction_engine.dart';
import '../../../../core/network/mosh_session_manager.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/network/terminal_mosh_bridge.dart';
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

  /// The host this tab connects to. Not final: a reconnect re-reads the row so
  /// edits made after the tab was opened (a protocol switch, a new port) take
  /// effect instead of the snapshot from open time.
  HostModel? host;

  /// Decrypted credentials for [host]. Replaced alongside [host] when a
  /// reconnect finds the host now points at a different identity.
  IdentityModel? identity;
  final Terminal terminal;

  /// Shared owner of `terminal.onOutput`. Broadcast and the mobile extra-keys
  /// bar register interceptors here instead of wrapping the slot themselves,
  /// which is what lets them be added and removed independently and survive a
  /// bridge reconnect.
  late final TerminalOutputChain outputChain = TerminalOutputChain(terminal);

  SSHSessionManager? sshSessionManager;

  /// Session managers for each hop of a `ProxyJump` chain, outermost first,
  /// kept alive alongside [sshSessionManager] since its transport tunnels
  /// through the last of these.
  List<SSHSessionManager> jumpSessionManagers = [];
  TerminalSSHBridge? sshBridge;

  /// Mosh transport for a `protocol: 'mosh'` tab. The SSH manager above stays
  /// connected alongside it — the bootstrap runs over that client, and SFTP and
  /// tunnels opened from this tab keep using it.
  MoshSessionManager? moshSessionManager;
  TerminalMoshBridge? moshBridge;

  /// Prediction state owned by this tab and shared with its Mosh bridge.
  /// SSH and local sessions keep the engine available but never render it.
  final MoshPredictionEngine moshPredictionEngine;

  /// Stream of invalidations for [moshPredictionEngine.visibleText]. It is a
  /// plain Dart stream so the domain model does not depend on Flutter UI
  /// notifiers; the terminal screen turns it into a repaint with StreamBuilder.
  final _moshPredictionChanges = StreamController<void>.broadcast();

  Stream<void> get moshPredictionChanges => _moshPredictionChanges.stream;

  /// Subscription to the Mosh link's liveness. Kept so the tab can show how
  /// long the server has been quiet; a stale link is never a disconnect.
  StreamSubscription<MoshLinkState>? moshLinkSub;

  /// Latest Mosh liveness snapshot, null on tabs that are not running Mosh.
  MoshLinkState? moshLinkState;

  /// True when this tab's shell is carried by Mosh rather than the SSH channel.
  bool get isMosh => moshBridge != null;

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
    MoshPredictionEngine? moshPredictionEngine,
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
  }) : moshPredictionEngine = moshPredictionEngine ?? MoshPredictionEngine();

  void syncMoshPredictionMode(MoshPredictionMode mode) {
    if (moshPredictionEngine.mode != mode) {
      moshPredictionEngine.mode = mode;
    }
    refreshMoshPredictionText();
  }

  void refreshMoshPredictionText() {
    // Read once so lazy timeout handling runs before the repaint event.
    moshPredictionEngine.visibleText;
    if (!_moshPredictionChanges.isClosed) {
      _moshPredictionChanges.add(null);
    }
  }

  /// Resizes the tab terminal and propagates dimensions to the active SSH or PTY session bridge.
  void resizeTerminal(
    int width,
    int height, [
    int pixelWidth = 0,
    int pixelHeight = 0,
  ]) {
    terminal.resize(width, height);
    sshBridge?.resizeTerminal(width, height, pixelWidth, pixelHeight);
    moshBridge?.resizeTerminal(width, height, pixelWidth, pixelHeight);
    ptyBridge?.resizeTerminal(width, height);
  }

  Future<void> dispose() async {
    moshPredictionEngine.reset();
    refreshMoshPredictionText();
    outputChain.dispose();
    await sshClientChangesSub?.cancel();
    sshClientChangesSub = null;
    await moshLinkSub?.cancel();
    moshLinkSub = null;
    if (sshBridge != null) {
      await sshBridge!.dispose(closeSession: true);
      sshBridge = null;
    }
    if (moshBridge != null) {
      await moshBridge!.dispose(closeSession: true);
      moshBridge = null;
    }
    if (moshSessionManager != null) {
      // Closed before the SSH manager: the bootstrap client is the one below,
      // and nothing about the UDP session outlives it.
      await moshSessionManager!.close();
      moshSessionManager = null;
    }
    if (ptyBridge != null) {
      await ptyBridge!.dispose(killPty: true);
      ptyBridge = null;
    }
    if (sshSessionManager != null) {
      await sshSessionManager!.close();
      sshSessionManager = null;
    }
    // Closed innermost-first (reverse of connect order): the target's own
    // manager is already down above, so nothing downstream depends on these
    // anymore when they close.
    for (final jumpManager in jumpSessionManagers.reversed) {
      await jumpManager.close();
    }
    jumpSessionManagers = [];
    await _moshPredictionChanges.close();
    // xterm3 guards write() against a disposed terminal, so late writes from
    // an in-flight connect do not crash after disposal.
    terminal.dispose();
  }
}
