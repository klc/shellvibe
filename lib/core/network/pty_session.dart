import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart';

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

  /// Signals the process.
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);

  /// Reports that a batch has been parsed and the next may be sent.
  ///
  /// This is the brake. Until it is called for a batch, the reader eventually
  /// stops acknowledging the PTY, the kernel's buffer fills, and the process
  /// writing into it blocks — which is the only thing that actually slows a
  /// producer down.
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

  /// Batches that may be in flight before the reader stops acknowledging the
  /// PTY.
  ///
  /// The credit window. macOS hands over at most 1024 bytes per read of a PTY
  /// master, so acknowledging per read would cost a round trip per KiB; this
  /// puts the round trip on the batch instead, which is two orders of
  /// magnitude less often.
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

  static const int write = 10;
  static const int resize = 11;
  static const int kill = 12;
  static const int acknowledge = 13;
  static const int dispose = 14;
}

/// Runs the PTY on its own isolate and delivers its output in batches.
///
/// The UI isolate cannot be the one reading a PTY. `flutter_pty` posts every
/// read as its own port message and macOS caps a read at 1024 bytes, so a
/// process producing at any speed buries the isolate in messages — measured at
/// 27,332 a second, which is an event loop that never empties long enough for
/// a frame to run. None of that work is the terminal's: it is a copy, a port
/// hop and a listener call per KiB.
///
/// Here the reading isolate absorbs that stream and hands the UI isolate
/// roughly a hundred batches a second instead. It is also where the
/// acknowledgement lives, so the brake costs a round trip per batch rather
/// than per KiB — and the round trip is cheap because this isolate has no
/// frames to draw while it waits.
class PtyIsolateSession implements PtySession {
  PtyIsolateSession._(this._isolate, this._commands, this._events, this._config);

  /// Starts the isolate and the process on it.
  ///
  /// Completes once the process exists, so a caller that gets a session has a
  /// process, and a failure to spawn surfaces here rather than as silence.
  static Future<PtyIsolateSession> start(PtySessionConfig config) async {
    final events = ReceivePort();
    final isolate = await Isolate.spawn(
      _readerMain,
      [events.sendPort, config],
      debugName: 'pty-reader',
    );

    final stream = events.asBroadcastStream();
    final first = await stream.first as List<Object?>;
    if (first[0] == _Wire.failure) {
      events.close();
      isolate.kill(priority: Isolate.immediate);
      throw PtySessionException(first[1]! as String);
    }

    return PtyIsolateSession._(
      isolate,
      first[1]! as SendPort,
      stream,
      config,
    );
  }

  final Isolate _isolate;
  final SendPort _commands;
  final Stream<Object?> _events;
  final PtySessionConfig _config;

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
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (_disposed) return false;
    _commands.send([_Wire.kill, _signalName(signal)]);
    return true;
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
    _commands.send([_Wire.dispose, kill]);
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (!_output.isClosed) await _output.close();
    if (!_exitCode.isCompleted) _exitCode.complete(-1);
    // The reader tears its own process down on the dispose message; killing
    // the isolate is the backstop for one that never got there.
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }

  /// The configuration this session was started with.
  PtySessionConfig get config => _config;
}

/// `ProcessSignal` is a class of constants rather than an enum, so it has no
/// index to send and no `values` to look one up in. Its `toString` is the
/// signal's name, and the handful a terminal ever sends map back cleanly.
String _signalName(ProcessSignal signal) => signal.toString();

ProcessSignal _signalByName(String name) => switch (name) {
  'SIGHUP' => ProcessSignal.sighup,
  'SIGINT' => ProcessSignal.sigint,
  'SIGQUIT' => ProcessSignal.sigquit,
  'SIGKILL' => ProcessSignal.sigkill,
  'SIGTERM' => ProcessSignal.sigterm,
  'SIGUSR1' => ProcessSignal.sigusr1,
  'SIGUSR2' => ProcessSignal.sigusr2,
  'SIGWINCH' => ProcessSignal.sigwinch,
  // Anything else falls back to the signal a terminal means by "stop".
  _ => ProcessSignal.sigterm,
};

/// Raised when the PTY could not be started, or died in a way that has to be
/// reported rather than delivered as output.
class PtySessionException implements Exception {
  const PtySessionException(this.message);

  final String message;

  @override
  String toString() => 'PtySessionException: $message';
}

/// Entry point of the reading isolate.
void _readerMain(List<Object?> args) {
  final events = args[0]! as SendPort;
  final config = args[1]! as PtySessionConfig;

  final Pty pty;
  try {
    pty = Pty.start(
      config.executable,
      arguments: config.arguments,
      workingDirectory: config.workingDirectory,
      environment: config.environment,
      rows: config.rows,
      columns: config.columns,
      // Acknowledged from this isolate, which has no frames to draw, so the
      // round trip costs microseconds rather than waiting behind a paint.
      ackRead: true,
    );
  } catch (e) {
    events.send([_Wire.failure, '$e']);
    return;
  }

  _Reader(pty: pty, events: events, config: config).run();
}

/// The reading side: absorbs the PTY's message-per-KiB stream, batches it, and
/// holds the acknowledgement when the far end has not kept up.
class _Reader {
  _Reader({required this.pty, required this.events, required this.config});

  final Pty pty;
  final SendPort events;
  final PtySessionConfig config;

  final _commands = ReceivePort();
  final _pending = BytesBuilder(copy: false);

  Timer? _flushTimer;
  int _outstanding = 0;
  int _ownedAcks = 0;
  bool _disposed = false;

  void run() {
    _commands.listen(_onCommand);
    events.send([_Wire.ready, _commands.sendPort]);

    pty.output.listen(
      _onChunk,
      onError: (Object error) => events.send([_Wire.failure, '$error']),
      onDone: _onDone,
    );

    unawaited(
      pty.exitCode.then((code) {
        _flush();
        events.send([_Wire.exit, code]);
      }).catchError((Object _) {
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

    // Read again unless the far end is already holding as much as it may.
    if (_outstanding < config.maxOutstandingBatches) {
      pty.ackRead();
    } else {
      _ownedAcks++;
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
  }

  void _onCommand(Object? message) {
    final command = message! as List<Object?>;
    switch (command[0]) {
      case _Wire.write:
        try {
          pty.write(command[1]! as Uint8List);
        } catch (e) {
          events.send([_Wire.failure, 'write: $e']);
        }
      case _Wire.resize:
        try {
          pty.resize(command[1]! as int, command[2]! as int);
        } catch (e) {
          events.send([_Wire.failure, 'resize: $e']);
        }
      case _Wire.kill:
        try {
          pty.kill(_signalByName(command[1]! as String));
        } catch (_) {
          // A process that is already gone needs no signal.
        }
      case _Wire.acknowledge:
        if (_outstanding > 0) _outstanding--;
        _releaseOwedAcks();
      case _Wire.dispose:
        _dispose(kill: command[1]! as bool);
    }
  }

  /// Lets the reader catch up on the reads it declined while the far end was
  /// full.
  ///
  /// Only one read can be outstanding at a time, so the debt is paid one
  /// acknowledgement per freed slot rather than all at once.
  void _releaseOwedAcks() {
    if (_ownedAcks == 0 || _outstanding >= config.maxOutstandingBatches) return;
    _ownedAcks--;
    // One acknowledgement releases exactly one read — the PTY holds a single
    // outstanding read at a time — and the chunk it produces decides for
    // itself whether to ask for another.
    pty.ackRead();
  }

  void _onDone() {
    _flush();
  }

  void _dispose({required bool kill}) {
    if (_disposed) return;
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    if (kill) {
      try {
        pty.kill();
      } catch (_) {}
    }
    _commands.close();
  }
}
