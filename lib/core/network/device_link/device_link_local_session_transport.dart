import 'dart:async';
import 'dart:typed_data';

import 'package:xterm3/xterm.dart';

import '../local_pty_manager.dart';
import 'device_link_attachment.dart';
import 'device_link_output_batcher.dart';
import 'device_link_protocol.dart';
import 'device_link_server.dart';
import 'device_link_session_transport.dart';
import 'device_link_snapshot.dart';

/// Adapter for the current local PTY session.
///
/// This file deliberately owns the `flutter_pty` dependency. The server and
/// transport contract stay pure Dart so the loopback smoke harness can run
/// with `dart run` without loading a platform FFI plugin.
///
/// Input from the phone is written straight to [ptyBridge.pty]. It does not
/// travel through xterm's `onOutput` callback, avoiding desktop broadcast and
/// sticky-key interceptors. PTY output is tapped before UTF-8 decoding and is
/// batched without dropping bytes.
///
/// The desktop keeps full use of the session while a phone is attached: both
/// ends write to the same process and both see everything it prints. Typing on
/// the desktop does not take the session back — sharing ends only when one end
/// explicitly disconnects.
final class DeviceLinkLocalSessionTransport
    implements DeviceLinkSessionTransport {
  @override
  final DeviceLinkSessionInfo info;
  final Terminal terminal;
  final TerminalLocalPtyBridge ptyBridge;
  final DeviceLinkAttachCallback attachSession;
  final DeviceLinkDetachCallback detachSession;
  final DeviceLinkResizeCallback resizeSession;
  final void Function()? onStateChanged;

  DeviceLinkServerConnection? _connection;
  DeviceLinkOutputBatcher? _batcher;
  bool _disposed = false;

  DeviceLinkLocalSessionTransport({
    required String sessionId,
    required String title,
    required this.terminal,
    required this.ptyBridge,
    required this.attachSession,
    required this.detachSession,
    required this.resizeSession,
    this.onStateChanged,
  }) : info = DeviceLinkSessionInfo(id: sessionId, title: title, type: 'local');

  @override
  bool get isAttached => _connection != null;

  @override
  Future<DeviceLinkSessionAttachResult> attach({
    required DeviceLinkServerConnection connection,
    required DeviceLinkAttach request,
  }) async {
    _ensureUsable();
    if (request.sessionId != info.id) {
      throw const DeviceLinkSessionException(
        'session_gone',
        'The requested terminal session is no longer available',
      );
    }
    if (_connection != null) {
      throw const DeviceLinkSessionException(
        'session_in_use',
        'The terminal session is already attached to another device',
      );
    }

    var sessionAttached = false;
    try {
      attachSession(
        connection.deviceId ?? 'unknown',
        request.cols,
        request.rows,
      );
      sessionAttached = true;
      _connection = connection;
      _batcher = DeviceLinkOutputBatcher(
        onFlush: (bytes) {
          final current = _connection;
          if (current == null || current.isClosed) return;
          unawaited(
            current
                .sendBinary(
                  DeviceLinkBinaryFrame(
                    type: DeviceLinkBinaryFrameType.ptyOutput,
                    payload: bytes,
                  ),
                )
                .catchError((_) {
                  // PTY output is best effort while the peer is disconnecting.
                  // The synchronous batcher callback must not leak a rejected
                  // send Future as an unhandled async error.
                }),
          );
        },
      );
      ptyBridge.outputTap = _batcher!.add;
      // The phone is attached to a process, not to a window. When that process
      // exits nothing else tells it, and the desktop would keep a "shared"
      // badge for a session that no longer exists.
      ptyBridge.onExit = _handlePtyExit;
      onStateChanged?.call();

      final snapshot = DeviceLinkSnapshot.capture(terminal);
      return DeviceLinkSessionAttachResult(
        attached: DeviceLinkAttached(
          sessionId: info.id,
          cols: terminal.viewWidth,
          rows: terminal.viewHeight,
          alt: snapshot.usingAlternateBuffer,
          bracketedPaste: snapshot.modes.bracketedPaste,
          scrollbackLines: snapshot.scrollbackLines,
        ),
        snapshotPayload: snapshot.toUtf8Bytes(),
      );
    } catch (_) {
      if (sessionAttached) {
        _detachInternal();
        onStateChanged?.call();
      }
      rethrow;
    }
  }

  @override
  Future<void> writeInput({
    required DeviceLinkServerConnection connection,
    required Uint8List bytes,
  }) async {
    _ensureOwnedBy(connection);
    if (bytes.isEmpty) return;
    try {
      ptyBridge.session.write(bytes);
    } catch (error) {
      throw DeviceLinkSessionException(
        'input_failed',
        'Could not write Device Link input to the PTY',
        error,
      );
    }
  }

  @override
  Future<void> resize({
    required DeviceLinkServerConnection connection,
    required int columns,
    required int rows,
  }) async {
    _ensureOwnedBy(connection);
    resizeSession(columns, rows);
  }

  @override
  Future<DeviceLinkAttachment?> detach({
    required DeviceLinkServerConnection connection,
  }) async {
    // Releasing must work even when the session underneath has died: a shell
    // that exits disposes the bridge, and refusing to detach after that would
    // strand the attachment — the desktop keeps a "shared" badge whose
    // disconnect button hits this same path and is refused in turn.
    if (!identical(_connection, connection)) {
      throw const DeviceLinkSessionException(
        'session_not_attached',
        'The Device Link connection does not own this session',
      );
    }
    final attachment = _detachInternal();
    onStateChanged?.call();
    return attachment;
  }

  /// Closes the owning connection so the server releases the attachment and
  /// restores the desktop terminal dimensions through the normal close path.
  Future<void> disconnect() async {
    await _connection?.close();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final connection = _connection;
    if (connection == null) return;

    // Clear the local owner before closing it. ServerConnection.close() calls
    // back into the server's attachment release path; clearing first makes
    // that callback observe an already-released transport instead of
    // recursively trying to detach it again.
    try {
      _detachInternal();
      onStateChanged?.call();
    } finally {
      // Closing the transport's owning connection is what tells the phone
      // that a desktop tab disappeared. The server-side close path is
      // idempotent, so this remains safe if a normal socket/PTY close races
      // with tab disposal.
      await connection.close();
    }
  }

  /// Ends the sharing when the process behind the session exits.
  ///
  /// The connection is closed rather than merely detached: the phone is
  /// mirroring a shell that is gone, and the socket closing is what tells it
  /// so through the path it already handles.
  void _handlePtyExit() {
    final connection = _connection;
    if (connection == null) return;
    _detachInternal();
    onStateChanged?.call();
    unawaited(connection.close());
  }

  DeviceLinkAttachment? _detachInternal() {
    ptyBridge.outputTap = null;
    ptyBridge.onExit = null;
    _batcher?.dispose();
    _batcher = null;
    _connection = null;
    return detachSession();
  }

  void _ensureUsable() {
    if (_disposed || ptyBridge.isDisposed) {
      throw const DeviceLinkSessionException(
        'session_gone',
        'The local PTY session is no longer available',
      );
    }
  }

  void _ensureOwnedBy(DeviceLinkServerConnection connection) {
    _ensureUsable();
    if (!identical(_connection, connection)) {
      throw const DeviceLinkSessionException(
        'session_not_attached',
        'The Device Link connection does not own this session',
      );
    }
  }
}
