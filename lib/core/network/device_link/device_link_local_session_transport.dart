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
  FutureOr<void> Function()? _onDesktopInput;
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
    required FutureOr<void> Function() onDesktopInput,
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
      _onDesktopInput = onDesktopInput;
      _batcher = DeviceLinkOutputBatcher(
        onFlush: (bytes) {
          final current = _connection;
          if (current == null || current.isClosed) return;
          unawaited(
            current.sendBinary(
              DeviceLinkBinaryFrame(
                type: DeviceLinkBinaryFrameType.ptyOutput,
                payload: bytes,
              ),
            ),
          );
        },
      );
      ptyBridge.outputTap = _batcher!.add;
      ptyBridge.inputTap = (_) {
        final callback = _onDesktopInput;
        if (callback != null) {
          unawaited(Future<void>.sync(callback));
        }
      };
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
      ptyBridge.pty.write(bytes);
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
    _ensureOwnedBy(connection);
    final attachment = _detachInternal();
    onStateChanged?.call();
    return attachment;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_connection != null) {
      _detachInternal();
      onStateChanged?.call();
    }
  }

  DeviceLinkAttachment? _detachInternal() {
    ptyBridge.outputTap = null;
    ptyBridge.inputTap = null;
    _onDesktopInput = null;
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
