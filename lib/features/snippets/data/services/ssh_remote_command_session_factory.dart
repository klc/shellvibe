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

    // Opens a fresh PTY-less shell over the still-authenticated client; used
    // for the first channel and as `reopen`, mirroring `McpSessionPool.open`.
    Future<ShellChannel> openPtylessShell() async {
      final session = await connection.target.openShell(requestPty: false);
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

  _SshRemoteCommandSession(this._shell, this._connection);

  @override
  Future<(String, int)> run(String command, Duration timeout) async {
    final result = await _shell.run(command, timeout: timeout);
    if (result.interrupted) {
      throw TimeoutException(
        'Command did not finish within ${timeout.inSeconds}s and was '
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
