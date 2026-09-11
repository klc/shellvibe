import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/device_link/device_link_output_batcher.dart';
import 'package:shellvibe/core/network/device_link/device_link_protocol.dart';

void main() {
  test('batches chunks without changing bytes or order', () async {
    final frames = <Uint8List>[];
    final batcher = DeviceLinkOutputBatcher(
      interval: const Duration(milliseconds: 1),
      onFlush: frames.add,
    );

    batcher.add(const [0x00, 0xFF]);
    batcher.add(const [0xC3, 0x28]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(frames, hasLength(1));
    expect(frames.single, orderedEquals(const [0x00, 0xFF, 0xC3, 0x28]));
    expect(batcher.pendingLength, 0);
    batcher.dispose();
  });

  test('dispose flushes pending bytes and rejects later chunks', () {
    final frames = <Uint8List>[];
    final batcher = DeviceLinkOutputBatcher(onFlush: frames.add);

    batcher.add(const [1, 2, 3]);
    batcher.dispose();
    batcher.add(const [4]);

    expect(frames, hasLength(1));
    expect(frames.single, orderedEquals(const [1, 2, 3]));
    expect(batcher.isClosed, isTrue);
  });

  test('splits oversized bursts without changing bytes or order', () {
    final frames = <Uint8List>[];
    final input = Uint8List.fromList(
      List<int>.generate(
        deviceLinkMaxPtyOutputPayloadLength * 2 + 17,
        (i) => i % 256,
      ),
    );
    final batcher = DeviceLinkOutputBatcher(onFlush: frames.add);

    batcher.add(input);
    batcher.dispose();

    expect(frames, hasLength(3));
    expect(
      frames.every(
        (frame) => frame.length <= deviceLinkMaxPtyOutputPayloadLength,
      ),
      isTrue,
    );
    expect(
      Uint8List.fromList(frames.expand((frame) => frame).toList()),
      orderedEquals(input),
    );
  });

  test('consumer errors do not break batching', () async {
    var calls = 0;
    final batcher = DeviceLinkOutputBatcher(
      interval: const Duration(milliseconds: 1),
      onFlush: (_) {
        calls++;
        throw StateError('consumer closed');
      },
    );

    batcher.add(const [1]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    batcher.add(const [2]);
    batcher.flush();

    expect(calls, 2);
    batcher.dispose();
  });
}
