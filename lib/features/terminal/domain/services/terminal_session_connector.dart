import 'dart:async';
import 'dart:io';

import 'package:dart_mosh/dart_mosh.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm3/xterm.dart';

import '../../../hosts/data/repositories/hosts_repository.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/domain/services/ssh_connect_planner.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../../core/network/mosh_session_manager.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/network/terminal_mosh_bridge.dart';
import '../../../../core/network/terminal_ssh_bridge.dart';
import '../../../../shared/database/daos/known_hosts_dao.dart';
import '../models/terminal_tab_session.dart';

/// Establishes SSH/Mosh sessions for a tab, reconnects a dropped one, and
/// reacts to their transport-level events (a lost keep-alive, the remote
/// shell exiting, a Mosh link update).
///
/// Owns none of the tabs or `TerminalTabsNotifier`'s `state`: every read of
/// "what does this tab/repository/identity look like right now" and every
/// write of "something changed, tell Riverpod" crosses through the
/// constructor callbacks below, so this class can run the actual connect
/// handshake without a Riverpod `ref` and the notifier keeps sole ownership
/// of `state`.
class TerminalSessionConnector {
  TerminalSessionConnector({
    required this.knownHostsDao,
    required this.hostsRepository,
    required this.fetchIdentityById,
    required this.decryptIdentityById,
    required this.findTab,
    required this.tabIsOpen,
    required this.notifyChanged,
    required this.syncBroadcast,
    required this.watchConnectivity,
  });

  final KnownHostsDao Function() knownHostsDao;
  final HostsRepository Function() hostsRepository;

  /// Resolves a jump host's identity while dialing a ProxyJump chain
  /// (`VaultRepository.getIdentityById`).
  final Future<IdentityModel?> Function(String identityId) fetchIdentityById;

  /// Resolves a tab's own identity when its host has changed on reconnect
  /// (`IdentitiesNotifier.getDecryptedIdentity`).
  final Future<IdentityModel?> Function(String identityId) decryptIdentityById;

  /// The live tab for an id, or null when it is no longer open.
  final TerminalTabSession? Function(String tabId) findTab;

  /// Whether a tab id is still present in the notifier's live `state.tabs`.
  final bool Function(String tabId) tabIsOpen;

  /// Tells the notifier a tab it owns changed, so it refreshes `state`.
  final void Function() notifyChanged;

  /// Reconciles broadcast interceptors with the current pane selection.
  final void Function() syncBroadcast;

  /// Starts watching for network changes, for the first Mosh session.
  final void Function() watchConnectivity;

  /// The planner that turns a stored host into a jump chain and a connect
  /// config, built fresh off the current [hostsRepository] on every access —
  /// matching how the notifier used to read the repository provider anew each
  /// time rather than caching a planner across a repository change.
  SshConnectPlanner get _connectPlanner => SshConnectPlanner(hostsRepository());

  Future<List<HostModel>> _resolveJumpChain(HostModel target) =>
      _connectPlanner.resolveJumpChain(target);

  SSHConnectConfig _buildConnectConfig(
    HostModel host,
    IdentityModel? identity, {
    HostKeyPromptCallback? onHostKeyPrompt,
  }) => _connectPlanner.buildConnectConfig(
    host,
    identity,
    onHostKeyPrompt: onHostKeyPrompt,
  );

  /// Opens an SSH shell on [tab] against [host] and wires the resulting
  /// session into the tab's terminal and bridge.
  ///
  /// Shared by `TerminalTabsNotifier.openTabForHost` and `splitTab` so that
  /// splitting an SSH host session opens a second SSH session to the same
  /// host (and keeps splits working on mobile, where a local PTY is not
  /// available).
  Future<void> connectSshTab(
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
              : await fetchIdentityById(jumpHost.identityId!);
          final jumpManager = SSHSessionManager(knownHostsDao: knownHostsDao());
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

      final sessionManager = SSHSessionManager(knownHostsDao: knownHostsDao());
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

        notifyChanged();
        // Wire broadcast if this pane is already part of the selection.
        syncBroadcast();
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
      notifyChanged();
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
      watchConnectivity();
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
    if (!tabIsOpen(tab.id)) return;
    tab.moshLinkState = linkState;
    notifyChanged();
  }

  /// Re-establishes the SSH session of a tab whose connection dropped or
  /// failed, re-reading the host so any edit made since the tab was opened
  /// applies, and reusing the stored host key prompt callback. The old bridge
  /// and manager are torn down first so a single live session per tab is
  /// preserved.
  Future<void> reconnectTab(String tabId) async {
    final tab = findTab(tabId);
    if (tab == null) return;
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
    notifyChanged();

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

    await connectSshTab(tab, host, tab.identity, tab.hostKeyPromptCallback);
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
      fresh = await hostsRepository().getHostById(hostId);
    } catch (_) {
      return;
    }
    if (fresh == null) return;

    if (fresh.identityId != tab.identity?.id) {
      try {
        tab.identity = fresh.identityId == null
            ? null
            : await decryptIdentityById(fresh.identityId!);
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
  /// the state (the manager also emits null during tab-close teardown).
  void _handleClientChange(TerminalTabSession tab, SSHClient? client) {
    if (client != null) return;
    if (!tab.isConnected) return;
    if (!tabIsOpen(tab.id)) return;
    _markTabDisconnected(tab, TerminalDisconnectCause.connectionLost);
  }

  /// Reacts to the bridge's remote streams ending: the shell on the other side
  /// exited. That is an ordinary end to a session, so it is recorded as such
  /// and not reported as a failure — the bridge has already written its own
  /// `[Session closed / Process exited]` notice to the buffer.
  void _handleRemoteExit(TerminalTabSession tab) {
    if (!tab.isConnected) return;
    if (!tabIsOpen(tab.id)) return;
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
    notifyChanged();
  }
}
