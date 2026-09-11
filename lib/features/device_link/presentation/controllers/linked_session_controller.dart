import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:xterm3/xterm.dart';

import '../../../../core/network/device_link/device_link_client.dart';
import '../../../../core/network/device_link/device_link_protocol.dart';
import '../../../../core/network/device_link/device_link_snapshot.dart';
import '../../../terminal/domain/models/terminal_tab_session.dart';
import '../../../terminal/domain/services/terminal_output_chain.dart';

enum DeviceLinkLinkedSessionStatus {
  connecting,
  attached,
  reclaimed,
  detached,
  disconnected,
  error,
}

/// Maximum number of input bytes retained by the serialized outbound queue.
///
/// This includes the logical input operation currently being sent as well as
/// operations waiting behind it. A new logical input is rejected in full when
/// it would exceed the budget, so a large paste can never be partially queued.
const int deviceLinkMaxQueuedInputBytes = 256 * 1024;

/// Owns the client-side terminal lifecycle for one linked desktop session.
///
/// The controller is independent of navigation and BuildContext. It converts
/// xterm input to raw Device Link bytes, applies the one-time snapshot, keeps
/// UTF-8 output chunk-safe, and blocks input as soon as desktop control is
/// reclaimed.
final class DeviceLinkLinkedSessionController extends ChangeNotifier {
  final DeviceLinkConnection connection;
  final DeviceLinkSessionInfo session;
  final TerminalTabSession terminalSession;
  final Terminal terminal;
  final TerminalOutputChain outputChain;

  late final ByteConversionSink _outputDecoder;
  StreamSubscription<DeviceLinkControlMessage>? _controlSubscription;
  StreamSubscription<DeviceLinkBinaryFrame>? _binarySubscription;
  bool _started = false;
  bool _closed = false;
  bool _applyingSnapshot = false;
  bool _bracketedPaste = true;
  int _columns;
  int _rows;

  /// The dimensions the phone's own terminal view last laid out at.
  ///
  /// The snapshot resizes the terminal to whatever the desktop had, and the
  /// view's render object only re-imposes its own size when the *viewport*
  /// changes — which it does not, because only the terminal moved. Remembering
  /// what the view asked for is what lets the snapshot be put back to the size
  /// this screen actually has.
  int? _viewColumns;
  int? _viewRows;

  DeviceLinkLinkedSessionStatus _status =
      DeviceLinkLinkedSessionStatus.connecting;
  String? _errorMessage;
  bool _readOnly = false;
  Future<void> _outboundTail = Future<void>.value();
  int _queuedInputBytes = 0;
  int _rejectedInputBytes = 0;

  factory DeviceLinkLinkedSessionController({
    required DeviceLinkConnection connection,
    required DeviceLinkSessionInfo session,
    String? terminalTabId,
    int columns = 52,
    int rows = 30,
    Terminal? terminal,
  }) {
    final actualTerminal = terminal ?? Terminal(maxLines: 10000);
    final actualTabSession = TerminalTabSession(
      id: terminalTabId ?? session.id,
      title: session.title,
      sessionType: TerminalSessionType.local,
      isDeviceLink: true,
      terminal: actualTerminal,
      isConnecting: true,
    );
    return DeviceLinkLinkedSessionController._(
      connection: connection,
      session: session,
      terminalSession: actualTabSession,
      columns: columns,
      rows: rows,
    );
  }

  DeviceLinkLinkedSessionController._({
    required this.connection,
    required this.session,
    required this.terminalSession,
    required int columns,
    required int rows,
  }) : _columns = columns,
       _rows = rows,
       terminal = terminalSession.terminal,
       outputChain = terminalSession.outputChain {
    if (columns <= 0) throw ArgumentError.value(columns, 'columns');
    if (rows <= 0) throw ArgumentError.value(rows, 'rows');
    terminal.resize(columns, rows);
    _outputDecoder = const Utf8Decoder(allowMalformed: true)
        .startChunkedConversion(
          StringConversionSink.from(
            _DeviceLinkTerminalOutputSink((text) {
              if (_closed || text.isEmpty) return;
              terminal.write(text);
            }),
          ),
        );
    terminal.onOutput = _handleTerminalOutput;
    // The desktop terminal is the one the program is talking to, and it
    // already answers every query it is sent. This terminal parses the same
    // byte stream, so without this its own device-attribute, cursor-position
    // and colour replies would be sent up as a second answer — which lands in
    // the shell as stray input, or leaves a full-screen program reading a
    // reply it never asked for.
    terminal.onReply = (_) {};
    // Adopt the handler as the chain base before the mobile extra-keys bar
    // installs its interceptor.
    outputChain.base;
    terminal.onResize = (width, height, _, _) {
      if (_closed || _applyingSnapshot) return;
      // Recorded even before the attach completes: the view usually lays out
      // first, and the attach has to carry this phone's real dimensions rather
      // than the placeholder the controller was built with.
      _viewColumns = width;
      _viewRows = height;
      if (width == _columns && height == _rows) return;
      _columns = width;
      _rows = height;
      if (_status != DeviceLinkLinkedSessionStatus.attached) return;
      unawaited(_sendResize(width, height));
    };
  }

  DeviceLinkLinkedSessionStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isReadOnly => _readOnly || connection.isReadOnly;
  bool get supportsBracketedPaste => _bracketedPaste;
  bool get canSendInput =>
      !_closed &&
      _status == DeviceLinkLinkedSessionStatus.attached &&
      !isReadOnly;
  int get queuedInputBytes => _queuedInputBytes;
  int get rejectedInputBytes => _rejectedInputBytes;

  /// Whether the peer still holds a session this controller can hand back.
  ///
  /// Not [canSendInput]: a reclaimed session is read-only for input yet stays
  /// attached on the desktop, so its disconnect button has to reach the peer.
  /// A session that already errored or detached has nothing left to release.
  bool get _canDetach =>
      !_closed &&
      !connection.isClosed &&
      (_status == DeviceLinkLinkedSessionStatus.attached ||
          _status == DeviceLinkLinkedSessionStatus.reclaimed);

  /// Begins the hello/attach listener and requests this session on the peer.
  Future<void> connect() async {
    if (_started || _closed) return;
    _started = true;
    _controlSubscription = connection.controlMessages.listen(
      _handleControl,
      onError: (Object error, StackTrace stack) => _setError(error.toString()),
      onDone: _handleConnectionClosed,
    );
    _binarySubscription = connection.binaryFrames.listen(
      _handleBinary,
      onError: (Object error, StackTrace stack) => _setError(error.toString()),
      onDone: _handleConnectionClosed,
    );
    try {
      await _enqueueOutbound(() async {
        if (_closed) return;
        await connection.sendAttach(
          DeviceLinkAttach(sessionId: session.id, cols: _columns, rows: _rows),
        );
      });
    } on Object catch (error) {
      _setError(error.toString());
    }
  }

  Future<void> sendText(String text) =>
      sendInput(Uint8List.fromList(utf8.encode(text)));

  Future<void> sendInput(Uint8List bytes) async {
    if (!canSendInput || bytes.isEmpty) return;
    if (!_reserveInputBytes(bytes.length)) return;

    var released = false;
    void releaseInputBytes() {
      if (released) return;
      released = true;
      _queuedInputBytes -= bytes.length;
    }

    try {
      await _enqueueOutbound(() async {
        try {
          // The state may have changed while an earlier outbound operation was
          // waiting. Keep this logical input operation all-or-nothing at the
          // controller boundary, without sending after detach/error/close.
          if (!canSendInput) return;
          for (var offset = 0; offset < bytes.length;) {
            if (!canSendInput) return;
            final remaining = bytes.length - offset;
            final chunkLength = remaining < deviceLinkMaxPtyInputPayloadLength
                ? remaining
                : deviceLinkMaxPtyInputPayloadLength;
            final end = offset + chunkLength;
            try {
              await connection.sendBinary(
                DeviceLinkBinaryFrame(
                  type: DeviceLinkBinaryFrameType.ptyInput,
                  payload: bytes.sublist(offset, end),
                ),
              );
            } on Object catch (error) {
              if (!connection.isReadOnly) _setError(error.toString());
              return;
            }
            offset = end;
          }
        } finally {
          releaseInputBytes();
        }
      });
    } on Object catch (error) {
      releaseInputBytes();
      if (!connection.isReadOnly) _setError(error.toString());
    }
  }

  /// Releases this session on the desktop.
  ///
  /// Deliberately not gated on [canSendInput]: a session the desktop has
  /// reclaimed is read-only for input but still attached, and its disconnect
  /// button has to reach the peer instead of silently dropping the socket.
  Future<void> detach() async {
    if (!_canDetach) return;
    await _enqueueOutbound(() async {
      if (!_canDetach) return;
      try {
        await connection.sendDetach();
      } catch (error) {
        _setError(error.toString());
        return;
      }
      _status = DeviceLinkLinkedSessionStatus.detached;
      _readOnly = true;
      terminalSession.isConnecting = false;
      terminalSession.isConnected = false;
      _notify();
    });
  }

  void _handleTerminalOutput(String data) {
    unawaited(_sendTerminalOutput(data));
  }

  Future<void> _sendTerminalOutput(String data) async {
    try {
      await sendText(data);
    } on Object catch (error) {
      if (!connection.isReadOnly) _setError(error.toString());
    }
  }

  void _handleControl(DeviceLinkControlMessage message) {
    if (_closed) return;
    switch (message) {
      case final DeviceLinkAttached attached:
        _columns = attached.cols;
        _rows = attached.rows;
        _status = DeviceLinkLinkedSessionStatus.attached;
        _readOnly = false;
        _bracketedPaste = attached.bracketedPaste;
        _errorMessage = null;
        terminalSession.isConnecting = false;
        terminalSession.isConnected = true;
        terminalSession.errorMessage = null;
        _notify();
        // The attach may have gone out before this screen was ever laid out,
        // in which case the desktop just sized the PTY to the placeholder
        // dimensions. Claim the real ones now.
        _restoreViewportSize();
      case DeviceLinkReclaimed():
        _readOnly = true;
        _status = DeviceLinkLinkedSessionStatus.reclaimed;
        terminalSession.isConnected = true;
        _notify();
      case DeviceLinkError(:final code, :final message):
        if (_isFatalErrorCode(code)) {
          _setError('$code: $message');
          return;
        }
        // A single failed write or resize says nothing about the session: it
        // is still attached and still usable. Surfacing it as a fatal error
        // would have the notifier close the connection and the tab over one
        // dropped keystroke, so it is reported and left at that.
        _errorMessage = '$code: $message';
        _notify();
      default:
        break;
    }
  }

  /// Error codes that mean this session is over. Anything else is a complaint
  /// about one message, not about the link.
  static const _fatalErrorCodes = {
    'unauthorized',
    'handshake_required',
    'unsupported_version',
    'session_gone',
    'session_in_use',
    'session_not_attached',
    'already_attached',
    'snapshot_too_large',
  };

  bool _isFatalErrorCode(String code) => _fatalErrorCodes.contains(code);

  void _handleBinary(DeviceLinkBinaryFrame frame) {
    if (_closed) return;
    switch (frame.type) {
      case DeviceLinkBinaryFrameType.snapshot:
        try {
          final decoded = jsonDecode(utf8.decode(frame.payload));
          if (decoded is! Map<String, Object?>) {
            throw const FormatException('snapshot payload must be an object');
          }
          final snapshot = DeviceLinkSnapshot.fromJson(decoded);
          _applyingSnapshot = true;
          snapshot.applyTo(terminal);
          _columns = snapshot.width;
          _rows = snapshot.height;
        } on Object catch (error) {
          _setError('Invalid terminal snapshot: $error');
        } finally {
          _applyingSnapshot = false;
        }
        _restoreViewportSize();
      case DeviceLinkBinaryFrameType.ptyOutput:
        _outputDecoder.add(frame.payload);
      case DeviceLinkBinaryFrameType.ptyInput:
        _setError('Unexpected input frame from desktop');
    }
  }

  /// Puts the terminal back to the size this phone's screen has after a
  /// snapshot resized it to the desktop's.
  ///
  /// Without this the grid keeps the desktop's row and column count, which on
  /// a phone leaves a blank strip down the side and along the bottom — the
  /// terminal is simply smaller than the space it is painted in. The desktop
  /// is told about the size too, so the PTY follows the phone.
  void _restoreViewportSize() {
    if (_closed) return;
    final columns = _viewColumns;
    final rows = _viewRows;
    if (columns == null || rows == null) return;
    if (columns == _columns && rows == _rows) return;
    _columns = columns;
    _rows = rows;
    terminal.resize(columns, rows);
    if (_status == DeviceLinkLinkedSessionStatus.attached) {
      unawaited(_sendResize(columns, rows));
    }
  }

  Future<void> _sendResize(int width, int height) async {
    await _enqueueOutbound(() async {
      if (_closed || _status != DeviceLinkLinkedSessionStatus.attached) return;
      try {
        await connection.sendResize(
          DeviceLinkResize(cols: width, rows: height),
        );
      } on Object catch (error) {
        if (!connection.isReadOnly) _setError(error.toString());
      }
    });
  }

  /// Serializes outbound operations without allowing one failed operation to
  /// block the operations queued after it. Input is queued as one operation,
  /// so its individual frames cannot be interleaved with another send.
  Future<void> _enqueueOutbound(Future<void> Function() operation) {
    final previous = _outboundTail;
    final completed = Completer<void>();
    _outboundTail = completed.future;

    return () async {
      try {
        await previous;
      } catch (_) {}
      try {
        await operation();
      } finally {
        completed.complete();
      }
    }();
  }

  bool _reserveInputBytes(int length) {
    if (length > deviceLinkMaxQueuedInputBytes ||
        _queuedInputBytes > deviceLinkMaxQueuedInputBytes - length) {
      _rejectedInputBytes += length;
      return false;
    }
    _queuedInputBytes += length;
    return true;
  }

  void _handleConnectionClosed() {
    if (_closed || _status == DeviceLinkLinkedSessionStatus.detached) return;
    _status = DeviceLinkLinkedSessionStatus.disconnected;
    _readOnly = true;
    terminalSession.isConnecting = false;
    terminalSession.isConnected = false;
    _notify();
  }

  void _setError(String message) {
    if (_closed) return;
    _status = DeviceLinkLinkedSessionStatus.error;
    _readOnly = true;
    _errorMessage = message;
    terminalSession.isConnecting = false;
    terminalSession.isConnected = false;
    terminalSession.errorMessage = message;
    _notify();
  }

  void _notify() {
    if (!hasListeners || _closed) return;
    notifyListeners();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _controlSubscription?.cancel();
    await _binarySubscription?.cancel();
    _controlSubscription = null;
    _binarySubscription = null;
    try {
      _outputDecoder.close();
    } catch (_) {}
    terminal.onOutput = null;
    terminal.onReply = null;
    terminal.onResize = null;
    outputChain.dispose();
    await connection.close();
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

/// Forwards every decoded UTF-8 chunk immediately instead of accumulating it
/// until the conversion sink is closed. Device Link connections are long
/// lived, so a callback sink would keep all live PTY output buffered forever.
final class _DeviceLinkTerminalOutputSink implements Sink<String> {
  final void Function(String text) _onData;

  _DeviceLinkTerminalOutputSink(this._onData);

  @override
  void add(String data) => _onData(data);

  @override
  void close() {}
}
