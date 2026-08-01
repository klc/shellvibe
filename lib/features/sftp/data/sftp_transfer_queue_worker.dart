import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:uuid/uuid.dart';
import '../domain/models/transfer_item.dart';

/// Worker managing background SFTP file uploads and downloads queue.
class SftpTransferQueueWorker {
  static const int _maxConcurrentTransfers = 3;

  final Map<String, TransferItem> _queue = {};
  final Map<String, bool> _cancelFlags = {};
  final Map<String, bool> _pauseFlags = {};
  int _activeTransferCount = 0;
  final List<_PendingTransfer> _pendingTransfers = [];

  final StreamController<List<TransferItem>> _queueController =
      StreamController<List<TransferItem>>.broadcast();

  /// Stream of transfer items queue
  Stream<List<TransferItem>> watchQueue() async* {
    yield queueList;
    yield* _queueController.stream;
  }

  /// Current queue list
  List<TransferItem> get queueList => _queue.values.toList();

  /// Enqueue download task (remote file -> local path)
  String enqueueDownload({
    required SftpClient client,
    required String remotePath,
    required String localPath,
    required int size,
  }) {
    final fileName = remotePath.split('/').last;
    final id = const Uuid().v4();

    final item = TransferItem(
      id: id,
      fileName: fileName,
      sourcePath: remotePath,
      destinationPath: localPath,
      totalBytes: size,
      type: TransferType.download,
      status: TransferStatus.pending,
    );

    _queue[id] = item;
    _notifyQueue();
    _scheduleTransfer(client, id);
    return id;
  }

  /// Enqueue upload task (local path -> remote file)
  String enqueueUpload({
    required SftpClient client,
    required String localPath,
    required String remotePath,
  }) {
    final file = File(localPath);
    final size = file.existsSync() ? file.lengthSync() : 0;
    final fileName = localPath.split(Platform.pathSeparator).last;
    final id = const Uuid().v4();

    final item = TransferItem(
      id: id,
      fileName: fileName,
      sourcePath: localPath,
      destinationPath: remotePath,
      totalBytes: size,
      type: TransferType.upload,
      status: TransferStatus.pending,
    );

    _queue[id] = item;
    _notifyQueue();
    _scheduleTransfer(client, id);
    return id;
  }

  /// Pause a running or pending transfer
  void pauseTransfer(String id) {
    if (_queue.containsKey(id)) {
      _pauseFlags[id] = true;
      _queue[id] = _queue[id]!.copyWith(status: TransferStatus.paused, speedBytesPerSec: 0);
      _notifyQueue();
    }
  }

  /// Resume a paused transfer
  void resumeTransfer(SftpClient client, String id) {
    if (_queue.containsKey(id)) {
      _pauseFlags[id] = false;
      _queue[id] = _queue[id]!.copyWith(status: TransferStatus.pending);
      _notifyQueue();
      _scheduleTransfer(client, id);
    }
  }

  /// Cancel a transfer
  void cancelTransfer(String id) {
    if (_queue.containsKey(id)) {
      _cancelFlags[id] = true;
      _queue[id] = _queue[id]!.copyWith(status: TransferStatus.cancelled, speedBytesPerSec: 0);
      _notifyQueue();
    }
  }

  /// Retry a failed or cancelled transfer
  void retryTransfer(SftpClient client, String id) {
    if (_queue.containsKey(id)) {
      _cancelFlags[id] = false;
      _pauseFlags[id] = false;
      _queue[id] = _queue[id]!.copyWith(
        status: TransferStatus.pending,
        transferredBytes: 0,
        error: null,
      );
      _notifyQueue();
      _scheduleTransfer(client, id);
    }
  }

  /// Clear completed or cancelled transfers from list
  void clearFinished() {
    _queue.removeWhere((id, item) =>
        item.status == TransferStatus.completed || item.status == TransferStatus.cancelled);
    _notifyQueue();
  }

  Future<void> _processQueue(SftpClient client, String targetId) async {
    final item = _queue[targetId];
    if (item == null || item.status != TransferStatus.pending) return;

    _queue[targetId] = item.copyWith(status: TransferStatus.inProgress);
    _notifyQueue();

    final stopwatch = Stopwatch()..start();

    try {
      if (item.type == TransferType.download) {
        await _performDownload(client, targetId, stopwatch, (transferred, speed) {
          _updateProgress(targetId, transferred, speed);
        });
      } else {
        await _performUpload(client, targetId, stopwatch, (transferred, speed) {
          _updateProgress(targetId, transferred, speed);
        });
      }

      if (_cancelFlags[targetId] == true) {
        _queue[targetId] = _queue[targetId]!
            .copyWith(status: TransferStatus.cancelled, speedBytesPerSec: 0);
      } else if (_pauseFlags[targetId] == true) {
        _queue[targetId] =
            _queue[targetId]!.copyWith(status: TransferStatus.paused, speedBytesPerSec: 0);
      } else {
        _queue[targetId] = _queue[targetId]!.copyWith(
          status: TransferStatus.completed,
          transferredBytes: _queue[targetId]!.totalBytes,
          speedBytesPerSec: 0,
        );
      }
    } catch (e) {
      _queue[targetId] = _queue[targetId]!.copyWith(
        status: TransferStatus.failed,
        error: e.toString(),
        speedBytesPerSec: 0,
      );
    } finally {
      stopwatch.stop();
      _activeTransferCount--;
      _notifyQueue();
      _drainPending();
    }
  }

  /// Schedules a transfer, respecting the concurrency limit.
  void _scheduleTransfer(SftpClient client, String id) {
    if (_activeTransferCount < _maxConcurrentTransfers) {
      _activeTransferCount++;
      _processQueue(client, id);
    } else {
      _pendingTransfers.add(_PendingTransfer(client: client, id: id));
    }
  }

  /// Starts waiting transfers when a slot opens.
  void _drainPending() {
    while (_pendingTransfers.isNotEmpty &&
        _activeTransferCount < _maxConcurrentTransfers) {
      final pending = _pendingTransfers.removeAt(0);
      final item = _queue[pending.id];
      if (item != null && item.status == TransferStatus.pending) {
        _activeTransferCount++;
        _processQueue(pending.client, pending.id);
      }
    }
  }

  Future<void> _performDownload(
    SftpClient client,
    String id,
    Stopwatch stopwatch,
    void Function(int transferred, int speed) onProgress,
  ) async {
    final item = _queue[id]!;
    final remoteFile = await client.open(item.sourcePath, mode: SftpFileOpenMode.read);

    try {
      final localFile = File(item.destinationPath);
      await localFile.parent.create(recursive: true);
      final sink = localFile.openWrite(mode: FileMode.write);

      int transferred = 0;
      int lastTimeMs = stopwatch.elapsedMilliseconds;
      int lastTransferred = 0;

      try {
        final stream = remoteFile.read();
        await for (final chunk in stream) {
          if (_cancelFlags[id] == true || _pauseFlags[id] == true) {
            break;
          }
          sink.add(chunk);
          transferred += chunk.length;

          final nowMs = stopwatch.elapsedMilliseconds;
          final deltaMs = nowMs - lastTimeMs;
          int speed = item.speedBytesPerSec;
          if (deltaMs >= 500) {
            speed = ((transferred - lastTransferred) * 1000) ~/ deltaMs;
            lastTimeMs = nowMs;
            lastTransferred = transferred;
          }

          onProgress(transferred, speed);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
    } finally {
      await remoteFile.close();
    }
  }

  Future<void> _performUpload(
    SftpClient client,
    String id,
    Stopwatch stopwatch,
    void Function(int transferred, int speed) onProgress,
  ) async {
    final item = _queue[id]!;
    final localFile = File(item.sourcePath);
    if (!await localFile.exists()) {
      throw Exception('Local file does not exist: ${item.sourcePath}');
    }

    final remoteFile = await client.open(
      item.destinationPath,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
    );

    try {
      int transferred = 0;
      int lastTimeMs = stopwatch.elapsedMilliseconds;
      int lastTransferred = 0;

      final stream = localFile.openRead();
      await for (final chunk in stream) {
        if (_cancelFlags[id] == true || _pauseFlags[id] == true) {
          break;
        }

        final uint8Chunk = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        await remoteFile.write(Stream.value(uint8Chunk), offset: transferred);
        transferred += uint8Chunk.length;

        final nowMs = stopwatch.elapsedMilliseconds;
        final deltaMs = nowMs - lastTimeMs;
        int speed = item.speedBytesPerSec;
        if (deltaMs >= 500) {
          speed = ((transferred - lastTransferred) * 1000) ~/ deltaMs;
          lastTimeMs = nowMs;
          lastTransferred = transferred;
        }

        onProgress(transferred, speed);
      }
    } finally {
      await remoteFile.close();
    }
  }

  void _updateProgress(String id, int transferredBytes, int speedBytesPerSec) {
    if (_queue.containsKey(id)) {
      _queue[id] = _queue[id]!.copyWith(
        transferredBytes: transferredBytes,
        speedBytesPerSec: speedBytesPerSec,
      );
      _notifyQueue();
    }
  }

  void _notifyQueue() {
    if (!_queueController.isClosed) {
      _queueController.add(queueList);
    }
  }

  void dispose() {
    _queueController.close();
  }
}

/// Holds a transfer that is waiting for a concurrency slot.
class _PendingTransfer {
  final SftpClient client;
  final String id;

  const _PendingTransfer({required this.client, required this.id});
}
