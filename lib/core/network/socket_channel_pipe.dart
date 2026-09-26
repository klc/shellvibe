import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Upper bound for flushing what is still queued for the local socket once
/// the forward is torn down. A client that stopped reading would otherwise
/// hold the socket open forever.
const _kSocketFlushTimeout = Duration(seconds: 10);

/// Pipes bytes both ways between a local TCP [socket] and an SSH forward
/// [channel], the way OpenSSH does for `-L`, `-R` and `-D` forwards.
///
/// End of stream travels on its own in each direction. A peer that shuts
/// down only its sending side (`nc -N`, `printf … | nc`, HTTP/1.0 and RPC
/// clients) just sends EOF to the other side, and the reply still on its way
/// back is delivered. The connection is torn down once both directions have
/// ended, once the channel is closed, or on an error from either side.
class SocketChannelPipe {
  SocketChannelPipe({
    required this.socket,
    required this.channel,
    this.onBytes,
    this.onClosed,
  });

  final Socket socket;
  final SSHForwardChannel channel;

  /// Called with the size of every chunk moved in either direction.
  final void Function(int bytes)? onBytes;

  /// Called once, after the connection has been torn down.
  final void Function()? onClosed;

  StreamSubscription<Uint8List>? _socketSub;
  StreamSubscription<Uint8List>? _channelSub;
  Future<void>? _socketWriteClosed;
  bool _socketEnded = false;
  bool _channelEnded = false;
  bool _channelClosed = false;
  bool _finished = false;

  bool get isClosed => _finished;

  /// Starts piping.
  ///
  /// A [Socket] can be listened to only once, even after the first
  /// subscription is cancelled. A caller that already read from [socket]
  /// passes that subscription as [socketSubscription] so it is taken over,
  /// together with the bytes it read but did not consume ([initialBytes])
  /// and whether the socket had already reached end of stream
  /// ([socketEnded]).
  void start({
    StreamSubscription<Uint8List>? socketSubscription,
    Uint8List? initialBytes,
    bool socketEnded = false,
  }) {
    if (initialBytes != null && initialBytes.isNotEmpty) {
      _toChannel(initialBytes);
    }

    _socketSub = (socketSubscription ?? socket.listen(null))
      ..onData(_toChannel)
      ..onError((Object _) => close())
      ..onDone(_onSocketDone);
    if (_socketSub!.isPaused) _socketSub!.resume();

    _channelSub = channel.stream.listen(
      _toSocket,
      onError: (Object _) => close(),
      onDone: _onChannelDone,
    );

    channel.done.then(
      (_) => _onChannelClosed(),
      onError: (Object _) => _onChannelClosed(),
    );

    if (socketEnded) _onSocketDone();
  }

  /// Tears the connection down in both directions right away.
  void close() {
    if (_finished) return;
    _socketWriteClosed = null;
    _finish();
  }

  void _toChannel(Uint8List data) {
    if (_finished || _socketEnded) return;
    try {
      channel.sink.add(data);
      onBytes?.call(data.length);
    } catch (_) {
      close();
    }
  }

  void _toSocket(Uint8List data) {
    if (_finished || _channelEnded) return;
    try {
      socket.add(data);
      onBytes?.call(data.length);
    } catch (_) {
      close();
    }
  }

  /// The local peer will send nothing more: pass EOF on to the channel and
  /// keep delivering the reply.
  void _onSocketDone() {
    if (_finished || _socketEnded) return;
    _socketEnded = true;
    try {
      // Closing the sink sends EOF once the queued data has gone out.
      unawaited(channel.sink.close().catchError((Object _) {}));
    } catch (_) {}
    if (_channelEnded) _finish();
  }

  /// The remote peer will send nothing more: shut down the socket's sending
  /// side, which flushes what is still queued first.
  void _onChannelDone() {
    if (_finished || _channelEnded) return;
    _channelEnded = true;
    try {
      _socketWriteClosed = socket.close().catchError((Object _) {});
    } catch (_) {}
    if (_socketEnded || _channelClosed) _finish();
  }

  /// The channel is gone for good (both CLOSE messages exchanged). Wait for
  /// its stream to drain before tearing down, so a reply that arrived
  /// together with the CLOSE still reaches the socket.
  void _onChannelClosed() {
    if (_finished) return;
    _channelClosed = true;
    if (_channelEnded) _finish();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    unawaited(_socketSub?.cancel());
    unawaited(_channelSub?.cancel());
    try {
      unawaited(channel.close().catchError((Object _) {}));
    } catch (_) {}
    unawaited(_destroySocket(_socketWriteClosed));
  }

  Future<void> _destroySocket(Future<void>? flushed) async {
    if (flushed != null) {
      try {
        await flushed.timeout(_kSocketFlushTimeout);
      } catch (_) {}
    }
    try {
      socket.destroy();
    } catch (_) {}
    onClosed?.call();
  }
}
