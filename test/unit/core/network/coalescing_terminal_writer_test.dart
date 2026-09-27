import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/coalescing_terminal_writer.dart';
import 'package:xterm3/xterm.dart';

/// Records what actually reached [PacedTerminalWriter], which is the boundary
/// this class exists to change: not what the terminal ends up showing, but how
/// many writes it took to get there.
class _SpyPacedWriter extends PacedTerminalWriter {
  _SpyPacedWriter(super.terminal, {super.waitForFrame});

  final List<String> writes = <String>[];
  int flushCount = 0;

  @override
  void write(String data) {
    writes.add(data);
    super.write(data);
  }

  @override
  void flush() {
    flushCount++;
    super.flush();
  }
}

void main() {
  late Terminal terminal;
  late _SpyPacedWriter paced;
  late Completer<void> frame;

  /// Releases whatever is waiting on "the next frame" and lets the resulting
  /// microtasks run.
  Future<void> pumpFrame() async {
    final pending = frame;
    frame = Completer<void>();
    pending.complete();
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    terminal = Terminal()..resize(80, 24);
    frame = Completer<void>();
    paced = _SpyPacedWriter(terminal, waitForFrame: () => frame.future);
  });

  CoalescingTerminalWriter build({int maxWriteChars = 256 * 1024}) =>
      CoalescingTerminalWriter(
        paced,
        maxWriteChars: maxWriteChars,
        waitForFrame: () => frame.future,
      );

  test('a frame of small chunks becomes one write', () async {
    final writer = build();
    // What flutter_pty actually delivers: 1 KiB per Dart port message.
    for (var i = 0; i < 64; i++) {
      writer.write('x' * 1024);
    }

    // Nothing has reached the paced writer yet — the batch is still open.
    expect(paced.writes, isEmpty);

    await pumpFrame();

    expect(paced.writes.length, equals(1));
    expect(paced.writes.single.length, equals(64 * 1024));
  });

  test('output still arrives in order', () async {
    final writer = build();
    writer
      ..write('first ')
      ..write('second ')
      ..write('third');
    await pumpFrame();

    expect(paced.writes.single, equals('first second third'));
  });

  test('a batch past the cap hands over without waiting for the frame',
      () async {
    // A fast producer can deliver megabytes between two frames, and the paced
    // writer checks its budget between queued chunks — so one unbounded batch
    // would be parsed atomically and cost the stall this class removes.
    final writer = build(maxWriteChars: 4096);
    for (var i = 0; i < 4; i++) {
      writer.write('y' * 1024);
    }

    expect(paced.writes.length, equals(1));
    expect(paced.writes.single.length, equals(4096));
  });

  test('a flood queues several chunks, which is what the pacer paces',
      () async {
    final writer = build(maxWriteChars: 4096);
    for (var i = 0; i < 12; i++) {
      writer.write('z' * 1024);
    }

    // Three full batches handed over, none of them waiting on a frame.
    expect(paced.writes.length, equals(3));
    expect(paced.pendingChunks, greaterThan(0));
  });

  test('nothing is scheduled twice for one frame', () async {
    final writer = build();
    writer
      ..write('a')
      ..write('b');
    await pumpFrame();
    // A second frame with nothing buffered must not produce an empty write.
    await pumpFrame();

    expect(paced.writes, equals(['ab']));
  });

  test('each hand-over notifies the producer', () async {
    // A bridge holding a read acknowledgement as backpressure has no other
    // way to learn the buffer drained.
    var handOffs = 0;
    final writer = CoalescingTerminalWriter(
      paced,
      onHandOff: () => handOffs++,
      waitForFrame: () => frame.future,
    );

    writer.write('a');
    expect(handOffs, equals(0));

    await pumpFrame();
    expect(handOffs, equals(1));

    // A frame with nothing buffered is not a hand-over.
    await pumpFrame();
    expect(handOffs, equals(1));
  });

  test('a batch forced over the cap notifies too', () async {
    var handOffs = 0;
    final writer = CoalescingTerminalWriter(
      paced,
      maxWriteChars: 2048,
      onHandOff: () => handOffs++,
      waitForFrame: () => frame.future,
    );

    writer
      ..write('x' * 1024)
      ..write('x' * 1024);

    expect(handOffs, equals(1));
  });

  test('flush empties both stages now', () async {
    final writer = build()..write('urgent');
    writer.flush();

    expect(paced.writes, equals(['urgent']));
    expect(paced.flushCount, equals(1));
    expect(terminal.buffer.lines[0].toString(), contains('urgent'));
  });

  test('dispose drops what is buffered and ignores later writes', () async {
    final writer = build()..write('dropped');
    writer
      ..dispose()
      ..write('after');
    await pumpFrame();

    expect(paced.writes, isEmpty);
    expect(writer.hasPendingOutput, isFalse);
  });

  test('empty writes are not batches', () async {
    final writer = build()..write('');
    await pumpFrame();

    expect(paced.writes, isEmpty);
    expect(writer.bufferedChars, equals(0));
  });

  test('bufferedChars reports what has not been handed over yet', () async {
    final writer = build()..write('12345');

    expect(writer.bufferedChars, equals(5));
    expect(writer.hasPendingOutput, isTrue);

    await pumpFrame();
    expect(writer.bufferedChars, equals(0));
  });

  test('a non-positive cap is rejected rather than silently disabling the cap',
      () {
    expect(
      () => CoalescingTerminalWriter(paced, maxWriteChars: 0),
      throwsArgumentError,
    );
  });
}
