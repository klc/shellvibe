import 'package:flutter/widgets.dart';
import 'package:xterm2/xterm.dart';

import '../../../../core/network/local_pty_manager.dart';
import '../../../../core/network/ssh_session_manager.dart';
import '../../../../core/network/terminal_ssh_bridge.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../vault/domain/models/identity_model.dart';

enum TerminalSessionType { ssh, local }

/// Model representing an active terminal tab session.
class TerminalTabSession {
  final String id;
  final String title;
  final TerminalSessionType sessionType;
  final HostModel? host;
  final IdentityModel? identity;
  final Terminal terminal;
  SSHSessionManager? sshSessionManager;
  TerminalSSHBridge? sshBridge;
  TerminalLocalPtyBridge? ptyBridge;
  bool isConnecting;
  bool isConnected;
  String? errorMessage;
  final String? splitParentId;
  final Axis? splitDirection;

  TerminalTabSession({
    required this.id,
    required this.title,
    required this.sessionType,
    this.host,
    this.identity,
    required this.terminal,
    this.sshSessionManager,
    this.sshBridge,
    this.ptyBridge,
    this.isConnecting = false,
    this.isConnected = false,
    this.errorMessage,
    this.splitParentId,
    this.splitDirection,
  });

  /// Resizes the tab terminal and propagates dimensions to the active SSH or PTY session bridge.
  void resizeTerminal(int width, int height, [int pixelWidth = 0, int pixelHeight = 0]) {
    terminal.resize(width, height);
    sshBridge?.resizeTerminal(width, height, pixelWidth, pixelHeight);
    ptyBridge?.resizeTerminal(width, height);
  }

  Future<void> dispose() async {
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
  }
}
