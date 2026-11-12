import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm3/xterm.dart';

import '../../../../core/models/mosh_prediction_mode.dart';
import '../../../../core/network/device_link/device_link_attachment.dart';
import '../../../../core/network/device_link/device_link_session_transport.dart';
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

/// Which side of a pane another pane is being docked against.
enum PaneDockEdge {
  left,
  right,
  top,
  bottom;

  /// The axis a split along this edge lays its two panes out on.
  Axis get axis => this == PaneDockEdge.left || this == PaneDockEdge.right
      ? Axis.horizontal
      : Axis.vertical;

  /// Whether the docked pane takes the leading side (left, or top) of the
  /// split rather than the trailing one.
  bool get isLeading => this == PaneDockEdge.left || this == PaneDockEdge.top;
}

/// Model representing an active terminal tab session.
class TerminalTabSession {
  final String id;
  final String title;
  final TerminalSessionType sessionType;

  /// Id of the MCP session this tab is watching, or null on an ordinary tab.
  ///
  /// One field rather than a separate `isMcp` flag: an AI tab is defined by
  /// the session it mirrors, and everything the UI does differently here —
  /// refusing keyboard input, wearing the AI badge, killing the session when
  /// the user closes it — follows from there being one. Nothing in this tab
  /// owns a transport of its own; the MCP session pool writes into
  /// [terminal] and closing the tab closes that session, not a bridge here.
  final String? mcpSessionId;

  /// Whether this tab mirrors an agent's MCP session rather than a shell the
  /// user drives.
  bool get isMcp => mcpSessionId != null;

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
  final MoshPredictionEngine moshPredictionEngine = MoshPredictionEngine();

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
  DeviceLinkSessionTransport? deviceLinkTransport;
  DeviceLinkAttachment? attachment;
  bool isConnecting;
  bool isConnected;
  String? errorMessage;

  /// Startup snippet a template pane asks for, taking precedence over the
  /// host's own. Null means use the host's.
  String? startupSnippetOverrideId;

  /// Runbook a template pane asks to have typed in once connected, in place
  /// of any startup snippet.
  String? startupRunbookId;

  /// Set once the startup snippet has been dealt with for this tab, so that
  /// reconnecting the same tab never types it again.
  bool startupSnippetHandled = false;

  /// Set when a live session ended by itself. `remoteExit` is a normal
  /// shell exit and must not be reported as an error; `connectionLost` is a
  /// dropped transport. Null while connecting or connected, and for a session
  /// that never came up (that case carries [errorMessage] instead).
  TerminalDisconnectCause? disconnectCause;

  /// What the program in this pane last called its window (OSC 0/2): a shell
  /// reporting `user@host: ~/src`, an editor reporting the file it has open.
  /// Null until something reports one.
  String? reportedTitle;

  /// The directory the shell last reported (OSC 7), as a path; a local
  /// shell's home is written `~`. Null until the shell reports one.
  String? workingDirectory;

  /// The name the tab strip and pane header show: what the program reports,
  /// else the directory it is in, else the name the tab was opened with.
  /// [title] itself is never replaced, since templates and saved layouts
  /// store it.
  String get displayTitle {
    final reported = reportedTitle?.trim();
    if (reported != null && reported.isNotEmpty) return reported;
    final dir = workingDirectory;
    if (dir != null && dir.isNotEmpty) return directoryLabel(dir);
    return title;
  }

  /// The short form of a directory for a tab: its last segment, or `~` / `/`.
  static String directoryLabel(String path) {
    if (path == '~' || path == '/') return path;
    final segments = path.split('/').where((s) => s.isNotEmpty);
    return segments.isEmpty ? path : segments.last;
  }

  /// The path an OSC 7 report points at (`file://host/Users/me/src` →
  /// `/Users/me/src`), with [home] shortened to `~`. Null when it is not a
  /// path at all.
  static String? reportedPath(String uri, {String? home}) {
    final parsed = Uri.tryParse(uri);
    var path = parsed != null && parsed.hasScheme
        ? Uri.decodeComponent(parsed.path)
        : uri;
    if (path.isEmpty) return null;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (home != null && home.isNotEmpty) {
      if (path == home) return '~';
      if (path.startsWith('$home/')) return '~${path.substring(home.length)}';
    }
    return path;
  }

  /// Parent pane in the split tree, null for a tab root. Not final: closing a
  /// pane promotes its children in place — they keep their live terminal,
  /// bridges and subscriptions and only change position in the tree.
  String? splitParentId;

  /// How this pane was split off its parent. Cleared together with
  /// [splitParentId] when a pane is promoted to tab root.
  Axis? splitDirection;

  /// Share (0..1) of the split container taken by this pane; the sibling takes 1 - share.
  double splitRatio = 0.5;

  TerminalTabSession({
    required this.id,
    required this.title,
    required this.sessionType,
    this.mcpSessionId,
    this.host,
    this.identity,
    required this.terminal,
    this.hostKeyPromptCallback,
    this.isConnecting = false,
    this.isConnected = false,
    this.errorMessage,
    this.disconnectCause,
    this.splitParentId,
    this.splitDirection,
    this.splitRatio = 0.5,
  });

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

  /// Records desktop dimensions and gives temporary resize ownership to a
  /// Device Link client. All PTY/terminal resize operations still go through
  /// [resizeTerminal], so the local, SSH, and Mosh paths cannot diverge.
  DeviceLinkAttachment attachDeviceLink({
    required String deviceId,
    required int columns,
    required int rows,
    DateTime? attachedAt,
  }) {
    if (attachment != null) {
      throw StateError('Terminal session is already attached to Device Link');
    }
    final previous = DeviceLinkAttachment(
      deviceId: deviceId,
      previousColumns: terminal.viewWidth,
      previousRows: terminal.viewHeight,
      attachedAt: attachedAt ?? DateTime.now().toUtc(),
    );
    attachment = previous;
    resizeTerminal(columns, rows);
    return previous;
  }

  /// Restores the dimensions captured by [attachDeviceLink].
  DeviceLinkAttachment? detachDeviceLink() {
    final current = attachment;
    if (current == null) return null;
    attachment = null;
    resizeTerminal(current.previousColumns, current.previousRows);
    return current;
  }

  /// Tears down every transport behind this tab — subscriptions, bridges,
  /// Mosh/SSH/jump managers, the PTY — and leaves the terminal, output chain
  /// and Device Link attachment alone, so a reconnect can reuse them.
  ///
  /// A Mosh session cannot be reattached — the client holds the OCB counter
  /// state and the server's replay filter rejects an old sequence — so a
  /// reconnect always starts a fresh one.
  ///
  /// Every field is detached before the first await. A call still closing
  /// when a reconnect installs new transports (a drop's unawaited teardown,
  /// then a quick Reconnect) closes only what it took, never the new ones.
  Future<void> closeSessions() async {
    final clientChangesCancelled = sshClientChangesSub?.cancel();
    sshClientChangesSub = null;
    final linkCancelled = moshLinkSub?.cancel();
    moshLinkSub = null;
    moshLinkState = null;
    final ssh = sshBridge;
    sshBridge = null;
    final mosh = moshBridge;
    moshBridge = null;
    final moshManager = moshSessionManager;
    moshSessionManager = null;
    final pty = ptyBridge;
    ptyBridge = null;
    final sshManager = sshSessionManager;
    sshSessionManager = null;
    final jumps = jumpSessionManagers;
    jumpSessionManagers = [];

    await clientChangesCancelled;
    await linkCancelled;
    await ssh?.dispose(closeSession: true);
    await mosh?.dispose(closeSession: true);
    // Closed before the SSH manager: the bootstrap client is the one below,
    // and nothing about the UDP session outlives it.
    await moshManager?.close();
    await pty?.dispose(killPty: true);
    await sshManager?.close();
    // Closed innermost-first (reverse of connect order): the target's own
    // manager is already down above, so nothing downstream depends on these
    // anymore when they close.
    for (final jumpManager in jumps.reversed) {
      await jumpManager.close();
    }
  }

  Future<void> dispose() async {
    await deviceLinkTransport?.dispose();
    deviceLinkTransport = null;
    attachment = null;
    moshPredictionEngine.reset();
    refreshMoshPredictionText();
    outputChain.dispose();
    await closeSessions();
    await _moshPredictionChanges.close();
    // xterm3 guards write() against a disposed terminal, so late writes from
    // an in-flight connect do not crash after disposal.
    terminal.dispose();
  }
}
