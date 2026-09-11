import 'dart:async';
import 'dart:typed_data';

import 'device_link_protocol.dart';

/// Collects consecutive raw PTY chunks into one frame without dropping bytes.
///
/// PTY applications can redraw many times per second. Batching reduces WebSocket
/// frame overhead while preserving byte order and every byte in the stream.
final class DeviceLinkOutputBatcher {
  final Duration interval;
  final void Function(Uint8List bytes) onFlush;
  final BytesBuilder _pending = BytesBuilder(copy: false);
  Timer? _timer;
  bool _closed = false;

  DeviceLinkOutputBatcher({
    required this.onFlush,
    this.interval = const Duration(milliseconds: 40),
  }) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'must be positive');
    }
  }

  bool get isClosed => _closed;

  int get pendingLength => _pending.length;

  void add(List<int> bytes) {
    if (_closed || bytes.isEmpty) return;
    _pending.add(bytes);
    _timer ??= Timer(interval, flush);
  }

  /// Flushes all queued bytes immediately, preserving insertion order.
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;

    final bytes = _pending.takeBytes();
    for (var offset = 0; offset < bytes.length;) {
      final remaining = bytes.length - offset;
      final chunkLength = remaining < deviceLinkMaxPtyOutputPayloadLength
          ? remaining
          : deviceLinkMaxPtyOutputPayloadLength;
      final end = offset + chunkLength;
      // `takeBytes` already handed over a private Uint8List, and `sublist`
      // copies out of it, so the consumer never shares a buffer with the next
      // batch. Wrapping that in `Uint8List.fromList` would only copy twice.
      final chunk = offset == 0 && end == bytes.length
          ? bytes
          : bytes.sublist(offset, end);
      try {
        onFlush(chunk);
      } catch (_) {
        // A disconnected consumer must not make the PTY output stream fail.
      }
      offset = end;
    }
  }

  /// Stops future batching and delivers the final queued bytes.
  void dispose() {
    if (_closed) return;
    _closed = true;
    flush();
  }
}
