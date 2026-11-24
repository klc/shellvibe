import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

// Prefixed: the package exports its own `PtySession`, which this file's
// interface would otherwise shadow.
import 'package:flutter_pty2/flutter_pty2.dart' as pty2;

/// What a terminal bridge needs from a local shell process.
///
/// [PtyIsolateSession] is the implementation; the interface exists so a test
/// can stand in for a process without one.
abstract class PtySession {
  /// Output from the process, already batched.
  Stream<Uint8List> get output;

  /// Completes with the process's exit code.
  Future<int> get exitCode;

  /// Sends [data] to the process's stdin.
  void write(Uint8List data);

  /// Tells the process its window changed.
  void resize(int rows, int columns);

  /// Reports that a batch has been parsed and the next may be sent.
  ///
  /// This is the brake. Until it is called for a batch, the reader eventually
  /// stops taking the PTY's output, the PTY stops reading, the kernel's buffer
  /// fills, and the process writing into it blocks — which is the only thing
  /// that actually slows a producer down.
  void acknowledge();

  /// Stops reading and releases the process.
  Future<void> dispose({bool kill = true});
}

/// How a [PtyIsolateSession] should start its process.
///
/// Everything here crosses an isolate boundary, so it has to stay primitive.
class PtySessionConfig {
  const PtySessionConfig({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
    required this.rows,
    required this.columns,
    this.flushBytes = 64 * 1024,
    this.flushInterval = const Duration(milliseconds: 4),
    this.maxOutstandingBatches = 4,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final int rows;
  final int columns;

  /// Batch size that triggers a send without waiting for [flushInterval].
  final int flushBytes;

  /// How long output may sit in the reader before being sent on.
  ///
  /// Shorter than a frame, so a batch is always ready when the UI isolate
  /// comes to draw, without the reader posting a message per PTY read.
  final Duration flushInterval;

  /// Batches that may be in flight before the reader pauses the PTY's output.
  ///
  /// The credit window. `flutter_pty2` returns read credit as its listener
  /// takes output, so pausing that listener is what holds the PTY back; this
  /// puts the round trip to the UI isolate on the batch rather than the read.
  final int maxOutstandingBatches;
}

/// Message tags on the wire between the two isolates.
///
/// Small ints rather than an enum: an enum crosses fine but shows up in every
/// message as a heavier object, and this wire carries thousands of them.
class _Wire {
  static const int ready = 0;
  static const int data = 1;
  static const int exit = 2;
  static const int failure = 3;
  static const int disposed = 4;

  static const int write = 10;
  static const int resize = 11;
  static const int acknowledge = 13;
  static const int dispose = 14;
}

/// Runs the PTY on its own isolate and delivers its output in batches.
///
/// The UI isolate should not be the one reading a PTY. `flutter_pty2` 1.x
/// posted every read as its own port message and macOS caps a read at 1024
/// bytes, so a process producing at any speed buried the isolate in messages —
/// measured at 27,332 a second, an event loop that never empties long enough
/// for a frame to run. 3.1 coalesces Unix reads into chunks of up to 64 KiB,
/// which removes most of that, but the reading isolate still keeps the native
/// event traffic and the batching off the isolate that draws frames.
///
/// Here the reading isolate absorbs that stream and hands the UI isolate
/// roughly a hundred batches a second. It is also where the brake lives, so
/// holding the PTY back costs a round trip per batch — and the round trip is
/// cheap because this isolate has no frames to draw while it waits.
class PtyIsolateSession implements PtySession {
  PtyIsolateSession._(this._isolate, this._commands, this._port, this._events);

  /// Starts the isolate and the process on it.
  ///
  /// Completes once the process exists, so a caller that gets a session has a
  /// process, and a failure to spawn surfaces here rather than as silence.
  static Future<PtyIsolateSession> start(PtySessionConfig config) async {
    final events = ReceivePort();
    final isolate = await Isolate.spawn(_readerMain, [
      events.sendPort,
      config,
    ], debugName: 'pty-reader');

    final stream = events.asBroadcastStream();
    final first = await stream.first as List<Object?>;
    if (first[0] == _Wire.failure) {
      events.close();
      isolate.kill(priority: Isolate.immediate);
      throw PtySessionException(first[1]! as String);
    }

    return PtyIsolateSession._(isolate, first[1]! as SendPort, events, stream);
  }

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _port;
  final Stream<Object?> _events;

  final _output = StreamController<Uint8List>();
  final _exitCode = Completer<int>();

  StreamSubscription<Object?>? _eventSubscription;
  bool _disposed = false;
  bool _bound = false;

  @override
  Stream<Uint8List> get output {
    _bind();
    return _output.stream;
  }

  @override
  Future<int> get exitCode {
    _bind();
    return _exitCode.future;
  }

  void _bind() {
    if (_bound) return;
    _bound = true;
    _eventSubscription = _events.listen(_onEvent);
  }

  void _onEvent(Object? message) {
    final event = message! as List<Object?>;
    switch (event[0]) {
      case _Wire.data:
        // The batch was built on the other isolate and is handed over rather
        // than copied.
        final transfer = event[1]! as TransferableTypedData;
        if (!_output.isClosed) {
          _output.add(transfer.materialize().asUint8List());
        }
      case _Wire.exit:
        if (!_exitCode.isCompleted) _exitCode.complete(event[1]! as int);
        if (!_output.isClosed) _output.close();
      case _Wire.failure:
        if (!_output.isClosed) {
          _output.addError(PtySessionException(event[1]! as String));
        }
    }
  }

  @override
  void write(Uint8List data) {
    if (_disposed) return;
    _commands.send([_Wire.write, data]);
  }

  @override
  void resize(int rows, int columns) {
    if (_disposed) return;
    _commands.send([_Wire.resize, rows, columns]);
  }

  @override
  void acknowledge() {
    if (_disposed) return;
    _commands.send(const [_Wire.acknowledge]);
  }

  @override
  Future<void> dispose({bool kill = true}) async {
    if (_disposed) return;
    _disposed = true;
    // The reader kills the process and exits on its own, answering with
    // [_Wire.disposed]. `Isolate.kill` is delivered out of band, ahead of
    // queued messages, so killing first would race the dispose command and
    // could orphan the shell: its fds are process-wide and nothing sends it
    // SIGHUP. The kill below is only the backstop for a reader that never
    // answers.
    final acknowledged = _events
        .firstWhere(
          (event) => (event! as List<Object?>)[0] == _Wire.disposed,
          orElse: () => null,
        )
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
    _commands.send([_Wire.dispose, kill]);
    await acknowledged;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (!_output.isClosed) await _output.close();
    if (!_exitCode.isCompleted) _exitCode.complete(-1);
    _isolate.kill(priority: Isolate.immediate);
    _port.close();
  }
}

/// Raised when the PTY could not be started, or died in a way that has to be
/// reported rather than delivered as output.
class PtySessionException implements Exception {
  const PtySessionException(this.message);

  final String message;

  @override
  String toString() => 'PtySessionException: $message';
}

/// Entry point of the reading isolate.
Future<void> _readerMain(List<Object?> args) async {
  final events = args[0]! as SendPort;
  final config = args[1]! as PtySessionConfig;

  final pty2.PtySession pty;
  try {
    pty = await pty2.Pty.spawn(
      pty2.PtySpawnOptions(
        executable: config.executable,
        arguments: config.arguments,
        workingDirectory: config.workingDirectory,
        // The caller already merged the inherited environment with its own.
        environment: pty2.PtyEnvironment.replace(config.environment),
        size: pty2.PtySize(columns: config.columns, rows: config.rows),
      ),
    );
  } catch (e) {
    events.send([_Wire.failure, '$e']);
    return;
  }

  _Reader(pty: pty, events: events, config: config).run();
}

/// The reading side: batches the PTY's output, and pauses it when the far end
/// has not kept up.
class _Reader {
  _Reader({required this.pty, required this.events, required this.config});

  final pty2.PtySession pty;
  final SendPort events;
  final PtySessionConfig config;

  final _commands = ReceivePort();
  final _pending = BytesBuilder(copy: false);

  StreamSubscription<Uint8List>? _output;
  Timer? _flushTimer;
  int _outstanding = 0;
  bool _disposed = false;

  void run() {
    _commands.listen(_onCommand);
    events.send([_Wire.ready, _commands.sendPort]);

    _output = pty.output.listen(
      _onChunk,
      onError: (Object error) => events.send([_Wire.failure, '$error']),
      onDone: _flush,
    );

    // `done`, not `processExit`: it completes only once the output has been
    // delivered, so the exit cannot overtake the process's last bytes.
    unawaited(
      pty.done
          .then((exit) {
            _flush();
            events.send([_Wire.exit, _exitCode(exit)]);
          })
          .catchError((Object _) {
            _flush();
            events.send([_Wire.exit, -1]);
          }),
    );
  }

  void _onChunk(Uint8List chunk) {
    if (_disposed) return;
    _pending.add(chunk);

    if (_pending.length >= config.flushBytes) {
      _flush();
    } else {
      _flushTimer ??= Timer(config.flushInterval, () {
        _flushTimer = null;
        _flush();
      });
    }
  }

  void _flush() {
    if (_pending.isEmpty || _disposed) return;
    _flushTimer?.cancel();
    _flushTimer = null;
    _outstanding++;
    events.send([
      _Wire.data,
      TransferableTypedData.fromList([_pending.takeBytes()]),
    ]);
    // The far end holds as much as it may: stop taking output, so the PTY
    // runs out of credit and stops reading.
    final output = _output;
    if (_outstanding >= config.maxOutstandingBatches &&
        output != null &&
        !output.isPaused) {
      output.pause();
    }
  }

  void _onCommand(Object? message) {
    final command = message! as List<Object?>;
    switch (command[0]) {
      case _Wire.write:
        final data = command[1]! as Uint8List;
        // Queued natively and admitted in order, so a paste never blocks this
        // isolate. A write racing the process's exit is dropped quietly: the
        // exit is reported on its own.
        unawaited(
          pty.input.write(data).catchError((Object e) {
            if (_disposed || e is pty2.PtyClosedException) return;
            events.send([_Wire.failure, 'write: $e']);
          }),
        );
      case _Wire.resize:
        try {
          pty.resize(
            pty2.PtySize(columns: command[2]! as int, rows: command[1]! as int),
          );
        } catch (e) {
          events.send([_Wire.failure, 'resize: $e']);
        }
      case _Wire.acknowledge:
        if (_outstanding > 0) _outstanding--;
        final output = _output;
        if (_outstanding < config.maxOutstandingBatches &&
            output != null &&
            output.isPaused) {
          output.resume();
        }
      case _Wire.dispose:
        unawaited(_dispose(kill: command[1]! as bool));
    }
  }

  Future<void> _dispose({required bool kill}) async {
    if (_disposed) return;
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    _commands.close();
    // `close()` SIGKILLs whatever is still running, so [kill] only decides
    // whether the shell gets a hangup first; there is no way to release the
    // process and leave it alive.
    if (kill) await _hangUp();
    try {
      await _output?.cancel();
      // Closes the master fd and the native session; a closed tab would
      // otherwise leak them for good.
      await pty.close();
    } catch (_) {}
    // Exits with the acknowledgement so it cannot be lost behind the exit.
    Isolate.exit(events, const [_Wire.disposed]);
  }

  /// Sends the shell SIGHUP, what a closing terminal sends, and gives it a
  /// moment to exit.
  ///
  /// Interactive shells ignore the SIGTERM default, and `close()` would
  /// SIGKILL them, so without this a shell never gets to save its history or
  /// hang up its jobs. The wait stays well under the 2 s the UI isolate gives
  /// the whole dispose. Windows has no signals; `close()` ends the process
  /// tree there.
  Future<void> _hangUp() async {
    if (!pty.capabilities.posixSignals) return;
    try {
      pty.sendSignal(
        pty2.PosixSignal.hup,
        target: pty2.PosixSignalTarget.shellProcess,
      );
      await pty.processExit.timeout(const Duration(milliseconds: 500));
    } catch (_) {
      // Already exited, or did not exit in time: `close()` handles both.
    }
  }
}

/// The code a shell would report for [exit]: 128 plus the signal number for a
/// process a signal ended.
int _exitCode(pty2.PtyExit exit) => switch (exit) {
  pty2.PtyExitCode(:final code) => code,
  pty2.PtySignalExit(:final signal) => 128 + signal,
};
