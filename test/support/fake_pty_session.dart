import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellvibe/core/network/pty_session.dart';

/// A [PtySession] with no process behind it.
///
/// The test hands it output as the shell would produce it, and reads back
/// what was written to it and how many batches were acknowledged.
final class FakePtySession implements PtySession {
  FakePtySession({int exitCode = 0}) : exitCode = Future.value(exitCode);
  final _output = StreamController<Uint8List>();

  /// Every write, copied as it arrived.
  final List<Uint8List> writes = [];

  /// How many output batches the reader was told it may replace.
  int ackCount = 0;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  final Future<int> exitCode;

  @override
  void write(Uint8List data) => writes.add(Uint8List.fromList(data));

  @override
  void resize(int rows, int columns) {}

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  void acknowledge() => ackCount++;

  @override
  Future<void> dispose({bool kill = true}) => closeOutput();

  /// Delivers [bytes] as one batch of shell output.
  void emitOutput(List<int> bytes) => _output.add(Uint8List.fromList(bytes));

  /// Ends the output, as a shell that has exited does.
  Future<void> closeOutput() => _output.close();
}
