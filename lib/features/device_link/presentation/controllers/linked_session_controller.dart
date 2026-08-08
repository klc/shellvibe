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

  DeviceLinkLinkedSessionStatus _status =
      DeviceLinkLinkedSessionStatus.connecting;
  String? _errorMessage;
  bool _readOnly = false;

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
    // Adopt the handler as the chain base before the mobile extra-keys bar
    // installs its interceptor.
    outputChain.base;
    terminal.onResize = (width, height, _, _) {
      if (_closed ||
          _applyingSnapshot ||
          _status != DeviceLinkLinkedSessionStatus.attached) {
        return;
      }
      if (width == _columns && height == _rows) return;
      _columns = width;
      _rows = height;
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
      await connection.sendAttach(
        DeviceLinkAttach(sessionId: session.id, cols: _columns, rows: _rows),
      );
    } on Object catch (error) {
      _setError(error.toString());
    }
  }

  Future<void> sendText(String text) =>
      sendInput(Uint8List.fromList(utf8.encode(text)));

  Future<void> sendInput(Uint8List bytes) async {
    if (!canSendInput || bytes.isEmpty) return;
    try {
      await connection.sendBinary(
        DeviceLinkBinaryFrame(
          type: DeviceLinkBinaryFrameType.ptyInput,
          payload: bytes,
        ),
      );
    } on Object catch (error) {
      if (!connection.isReadOnly) _setError(error.toString());
    }
  }

  Future<void> detach() async {
    if (_closed || _status == DeviceLinkLinkedSessionStatus.detached) return;
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
  }

  void _handleTerminalOutput(String data) {
    unawaited(sendText(data));
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
      case DeviceLinkReclaimed():
        _readOnly = true;
        _status = DeviceLinkLinkedSessionStatus.reclaimed;
        terminalSession.isConnected = true;
        _notify();
      case DeviceLinkError(:final code, :final message):
        _setError('$code: $message');
      default:
        break;
    }
  }

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
      case DeviceLinkBinaryFrameType.ptyOutput:
        _outputDecoder.add(frame.payload);
      case DeviceLinkBinaryFrameType.ptyInput:
        _setError('Unexpected input frame from desktop');
    }
  }

  Future<void> _sendResize(int width, int height) async {
    try {
      await connection.sendResize(DeviceLinkResize(cols: width, rows: height));
    } on Object catch (error) {
      if (!connection.isReadOnly) _setError(error.toString());
    }
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
