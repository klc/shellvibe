import 'dart:async';

import '../../../../core/mcp/shell/persistent_shell_session.dart';
import '../../../../core/mcp/shell/shell_channel.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../mcp/data/mcp_host_connector.dart';
import '../../../mcp/domain/models/mcp_enums.dart';
import '../../../mcp/domain/models/mcp_models.dart';
import '../../domain/services/remote_command_session.dart';

/// Opens command sessions over the same SSH path the terminal and the MCP
/// server use ([McpHostConnector]: ProxyJump chain, identities, `known_hosts`),
/// so a runbook reaches exactly the hosts a terminal tab would and trusts
/// exactly the fingerprints the user has already accepted.
///
/// Mosh hosts connect over plain SSH, as MCP does: Mosh only changes how an
/// interactive terminal survives roaming, and a background command channel has
/// nothing to roam.
class SshRemoteCommandSessionFactory implements RemoteCommandSessionFactory {
  final McpHostConnector connector;

  SshRemoteCommandSessionFactory({required this.connector});

  @override
  Future<RemoteCommandSession> open(HostModel host) async {
    if (host.protocol == 'local') {
      throw RemoteCommandException(
        '"${host.label}" is a local shell, which cannot run background '
        'commands yet. Pick an SSH host.',
      );
    }

    final McpConnection connection;
    try {
      connection = await connector.connect(host);
    } on McpToolException catch (e) {
      // The connector's own wording addresses an AI agent; say the same thing
      // to the person running the runbook.
      if (e.code == McpErrorCode.hostKeyUntrusted) {
        throw RemoteCommandException(
          'Host key not trusted yet — connect to "${host.label}" once from '
          'the terminal to verify it.',
        );
      }
      throw RemoteCommandException(e.message);
    }

    // Opens a fresh PTY-less `/bin/sh` over the still-authenticated client;
    // used for the first channel and as `reopen`, mirroring
    // `McpSessionPool.open`.
    Future<ShellChannel> openPtylessShell() async {
      final session = await connection.target.openExec(
        PersistentShellSession.remoteCommand,
      );
      return SshShellChannel(session);
    }

    PersistentShellSession? shell;
    try {
      shell = PersistentShellSession(
        channel: await openPtylessShell(),
        reopen: openPtylessShell,
      );
      await shell.initialize();
    } catch (_) {
      await shell?.close();
      await connection.close();
      rethrow;
    }
    return _SshRemoteCommandSession(shell, connection);
  }
}

class _SshRemoteCommandSession implements RemoteCommandSession {
  final PersistentShellSession _shell;
  final McpConnection _connection;
  bool _closed = false;

  /// Set once a hung command forced a shell reset. Every later step on this
  /// host then fails without running: its `cd`/exports are gone, and the
  /// hung command may still be running detached, so a retry could start a
  /// second copy of it.
  bool _lostShell = false;

  _SshRemoteCommandSession(this._shell, this._connection);

  @override
  Future<(String, int)> run(String command, Duration timeout) async {
    if (_lostShell) {
      throw const RemoteCommandException(
        'Not run: an earlier step hung and the shell on this host was reset, '
        'so its `cd`/exports are gone.',
      );
    }
    final result = await _shell.run(command, timeout: timeout);
    // A command that ended the shell itself (`exit 0`, `set -e`) has a real
    // exit status; an unknown one means the connection dropped or a signal
    // killed the shell.
    final shellEnded =
        result.sessionReset && !result.interrupted && !result.timedOut;
    if (shellEnded && result.exitCode < 0) {
      throw const RemoteCommandException(
        'The shell ended without an exit status: the connection dropped or '
        'the shell was killed.',
      );
    }
    if (!shellEnded && (result.interrupted || result.sessionReset)) {
      if (result.sessionReset) _lostShell = true;
      throw TimeoutException(
        result.sessionReset
            ? 'Command hung; the shell was reset and earlier `cd`/exports '
                  'are gone.'
            : 'Command did not finish within ${timeout.inSeconds}s and was '
                  'interrupted.',
        timeout,
      );
    }
    final output = [
      result.stdout,
      result.stderr,
    ].where((part) => part.isNotEmpty).join('\n');
    return (output, result.exitCode);
  }

  @override
  Future<void> interrupt() => _shell.interrupt();

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _shell.close();
    } finally {
      await _connection.close();
    }
  }
}
