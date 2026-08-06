import 'package:flutter_pty/flutter_pty.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm3/xterm.dart';

import '../../../shared/providers/database_providers.dart';
import '../local_pty_manager.dart';
import '../ssh_session_manager.dart';
import '../terminal_ssh_bridge.dart';

part 'network_providers.g.dart';

/// Provider for [SSHSessionManager].
/// Note: [TerminalTabSession] instances instantiate dedicated [SSHSessionManager]
/// instances per connection to ensure tabs do not share SSH clients/sockets.
@riverpod
SSHSessionManager sshSessionManager(Ref ref) {
  final dao = ref.watch(knownHostsDaoProvider);
  return SSHSessionManager(knownHostsDao: dao);
}

/// Auto-disposing provider for [LocalPtyManager].
@riverpod
LocalPtyManager localPtyManager(Ref ref) {
  return LocalPtyManager();
}

/// Helper record for [TerminalSSHBridge] family parameters.
class TerminalSSHBridgeParams {
  final Terminal terminal;
  final SSHSession session;

  const TerminalSSHBridgeParams({
    required this.terminal,
    required this.session,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerminalSSHBridgeParams &&
          runtimeType == other.runtimeType &&
          terminal == other.terminal &&
          session == other.session;

  @override
  int get hashCode => terminal.hashCode ^ session.hashCode;
}

/// Auto-disposing family provider for [TerminalSSHBridge].
/// Cleanly disposes stream subscriptions and session resources when disposed.
@riverpod
TerminalSSHBridge terminalSSHBridge(
  Ref ref,
  TerminalSSHBridgeParams params,
) {
  final bridge = TerminalSSHBridge(
    terminal: params.terminal,
    session: params.session,
  );

  ref.onDispose(() {
    bridge.dispose(closeSession: true);
  });

  return bridge;
}

/// Helper record for [TerminalLocalPtyBridge] family parameters.
class TerminalPtyBridgeParams {
  final Terminal terminal;
  final Pty pty;

  const TerminalPtyBridgeParams({
    required this.terminal,
    required this.pty,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerminalPtyBridgeParams &&
          runtimeType == other.runtimeType &&
          terminal == other.terminal &&
          sessionPtyEquals(other);

  bool sessionPtyEquals(TerminalPtyBridgeParams other) =>
      terminal == other.terminal && pty == other.pty;

  @override
  int get hashCode => terminal.hashCode ^ pty.hashCode;
}

/// Auto-disposing family provider for [TerminalLocalPtyBridge].
/// Cleanly disposes PTY stream subscriptions and process resources when disposed.
@riverpod
TerminalLocalPtyBridge terminalPtyBridge(
  Ref ref,
  TerminalPtyBridgeParams params,
) {
  final bridge = TerminalLocalPtyBridge(
    terminal: params.terminal,
    pty: params.pty,
  );

  ref.onDispose(() {
    bridge.dispose(killPty: true);
  });

  return bridge;
}
