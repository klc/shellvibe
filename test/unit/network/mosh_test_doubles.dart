import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:terly2/core/network/mosh_session_manager.dart';

/// In-memory [MoshTransport] standing in for a real UDP session.
///
/// Shared by the bridge and manager tests: both need to drive silence, server
/// shutdown, and rehome without opening a socket.
class FakeMoshTransport implements MoshTransport {
  final _stdoutController = StreamController<List<int>>.broadcast();
  final _errorsController = StreamController<Object>.broadcast();
  final _doneCompleter = Completer<void>();

  final List<List<int>> sentBytes = [];
  int? resizedColumns;
  int? resizedRows;
  int rehomeCount = 0;
  bool isClosed = false;

  /// When set, [rehome] throws it instead of succeeding.
  Exception? rehomeError;

  /// Completes on entry to [rehome] and is awaited before it returns, so a test
  /// can hold a rebind in flight.
  Completer<void>? rehomeGate;

  Duration? _sinceLastHeard;
  bool _isServerShutdown = false;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<Object> get errors => _errorsController.stream;

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  Duration? get sinceLastHeard => _sinceLastHeard;

  @override
  bool get isServerShutdown => _isServerShutdown;

  @override
  Duration? get smoothedRtt => const Duration(milliseconds: 12);

  @override
  int send(List<int> data) {
    sentBytes.add(data);
    return sentBytes.length;
  }

  @override
  int resize(int columns, int rows) {
    resizedColumns = columns;
    resizedRows = rows;
    return sentBytes.length + 1;
  }

  @override
  Future<void> rehome() async {
    rehomeCount++;
    final gate = rehomeGate;
    if (gate != null) await gate.future;
    final error = rehomeError;
    if (error != null) throw error;
  }

  @override
  Future<void> close() async {
    if (isClosed) return;
    isClosed = true;
    await _stdoutController.close();
    await _errorsController.close();
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }

  void emitStdout(String data) => _stdoutController.add(utf8.encode(data));

  void emitBytes(List<int> bytes) => _stdoutController.add(bytes);

  void emitError(Object error) => _errorsController.add(error);

  /// Silence, as the manager sees it. Does not end the session.
  void setSilence(Duration? silence) => _sinceLastHeard = silence;

  /// The server announced it is going away: `done` completes while the streams
  /// stay open so pending output can still be drained.
  void serverShutdown() {
    _isServerShutdown = true;
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }
}

/// [SSHClient] stand-in that answers exactly one `runWithResult` call — the
/// `mosh-server new` bootstrap.
class FakeBootstrapClient implements SSHClient {
  FakeBootstrapClient({this.output = '', this.exitCode = 0, this.error});

  /// Combined output the fake `mosh-server` prints.
  final String output;
  final int? exitCode;

  /// When set, `runWithResult` throws it instead of returning.
  final Exception? error;

  final List<String> commands = [];

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async {
    commands.add(command);
    final failure = error;
    if (failure != null) throw failure;
    final bytes = Uint8List.fromList(utf8.encode(output));
    return SSHRunResult(
      output: bytes,
      stdout: bytes,
      stderr: Uint8List(0),
      exitCode: exitCode,
      exitSignal: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
