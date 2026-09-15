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

  /// Ids whose `_processQueue` run has not finished unwinding yet.
  ///
  /// Guards pause/resume/retry against starting a second execution of the
  /// same transfer while the previous run is still tearing down (flushing,
  /// closing remote file handles, deleting partials). Without it two runs can
  /// truncate and write the same destination concurrently, or a superseded
  /// run's completion can mark a deleted partial file as `completed`.
  final Set<String> _runningIds = {};

  /// Ids for which resume/retry was requested while the old run was still
  /// unwinding. The old run's completion consumes the latch and restarts the
  /// transfer exactly once.
  final Map<String, bool> _restartRequested = {};

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
      _queue[id] = _queue[id]!.copyWith(
        status: TransferStatus.paused,
        speedBytesPerSec: 0,
      );
      _notifyQueue();
    }
  }

  /// Resume a paused transfer
  void resumeTransfer(SftpClient client, String id) {
    final item = _queue[id];
    if (item == null) return;

    if (_runningIds.contains(id)) {
      // Previous run is still unwinding (a paused loop only breaks on the next
      // chunk arrival). Latch a restart instead of starting a duplicate run;
      // the old run's completion consumes the latch exactly once.
      _restartRequested[id] = true;
      return;
    }

    _pauseFlags.remove(id);
    _restartRequested.remove(id);
    _queue[id] = item.copyWith(status: TransferStatus.pending);
    _notifyQueue();
    _scheduleTransfer(client, id);
  }

  /// Cancel a transfer
  void cancelTransfer(String id) {
    if (_queue.containsKey(id)) {
      _cancelFlags[id] = true;
      _queue[id] = _queue[id]!.copyWith(
        status: TransferStatus.cancelled,
        speedBytesPerSec: 0,
      );
      _notifyQueue();
    }
  }

  /// Retry a failed or cancelled transfer
  void retryTransfer(SftpClient client, String id) {
    final item = _queue[id];
    if (item == null) return;

    if (_runningIds.contains(id)) {
      // Keep the cancel latch set so the old run tears down cleanly (including
      // partial-file cleanup), then restart from the completion path.
      _cancelFlags[id] = true;
      _restartRequested[id] = true;
      return;
    }

    _cancelFlags.remove(id);
    _pauseFlags.remove(id);
    _restartRequested.remove(id);
    _queue[id] = item.copyWith(
      status: TransferStatus.pending,
      transferredBytes: 0,
      speedBytesPerSec: 0,
      clearError: true,
    );
    _notifyQueue();
    _scheduleTransfer(client, id);
  }

  /// Clear completed or cancelled transfers from list
  void clearFinished() {
    _queue.removeWhere(
      (id, item) =>
          !_runningIds.contains(id) &&
          !_restartRequested.containsKey(id) &&
          (item.status == TransferStatus.completed ||
              item.status == TransferStatus.cancelled),
    );
    _notifyQueue();
  }

  Future<void> _processQueue(SftpClient client, String targetId) async {
    final stopwatch = Stopwatch();
    try {
      final item = _queue[targetId];
      if (item == null || item.status != TransferStatus.pending) return;

      _queue[targetId] = item.copyWith(status: TransferStatus.inProgress);
      _notifyQueue();
      stopwatch.start();

      try {
        if (item.type == TransferType.download) {
          await _performDownload(client, targetId, stopwatch, (
            transferred,
            speed,
          ) {
            _updateProgress(targetId, transferred, speed);
          });
        } else {
          await _performUpload(client, targetId, stopwatch, (
            transferred,
            speed,
          ) {
            _updateProgress(targetId, transferred, speed);
          });
        }
      } catch (e) {
        // A pending restart supersedes the failure report: the user already
        // asked to retry/resume, so the final status is decided by the restart.
        final current = _queue[targetId];
        if (_restartRequested[targetId] != true && current != null) {
          _queue[targetId] = current.copyWith(
            status: TransferStatus.failed,
            error: e.toString(),
            speedBytesPerSec: 0,
          );
        }
        return;
      }

      if (_restartRequested[targetId] == true) {
        // Terminal state is decided by the restart in [finally].
        return;
      }
      if (_cancelFlags[targetId] == true) {
        final current = _queue[targetId];
        if (current != null) {
          _queue[targetId] = current.copyWith(
            status: TransferStatus.cancelled,
            speedBytesPerSec: 0,
          );
        }
      } else if (_pauseFlags[targetId] == true) {
        final current = _queue[targetId];
        if (current != null) {
          _queue[targetId] = current.copyWith(
            status: TransferStatus.paused,
            speedBytesPerSec: 0,
          );
        }
      } else {
        final current = _queue[targetId];
        if (current != null) {
          _queue[targetId] = current.copyWith(
            status: TransferStatus.completed,
            transferredBytes: current.totalBytes,
            speedBytesPerSec: 0,
          );
        }
      }
    } finally {
      // Runs that exit early (item vanished, no longer pending, superseded by
      // a restart) must still release their slot — otherwise the counter and
      // `_runningIds` leak and the queue eventually deadlocks.
      stopwatch.stop();
      _runningIds.remove(targetId);
      _activeTransferCount--;

      if (_restartRequested[targetId] == true) {
        _cancelFlags.remove(targetId);
        _pauseFlags.remove(targetId);
        _restartRequested.remove(targetId);
        final item = _queue[targetId];
        if (item != null) {
          _queue[targetId] = item.copyWith(
            status: TransferStatus.pending,
            transferredBytes: 0,
            speedBytesPerSec: 0,
            clearError: true,
          );
          _notifyQueue();
          _scheduleTransfer(client, targetId);
        }
      } else {
        _notifyQueue();
        _drainPending();
      }
    }
  }

  /// Schedules a transfer, respecting the concurrency limit.
  void _scheduleTransfer(SftpClient client, String id) {
    // Never start a second execution for an id whose previous run is still
    // unwinding. resume/retry during that window latch a restart instead.
    if (_runningIds.contains(id)) return;
    if (_activeTransferCount < _maxConcurrentTransfers) {
      _activeTransferCount++;
      _runningIds.add(id);
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
        _runningIds.add(pending.id);
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
    final item = _queue[id];
    if (item == null) return;

    final remoteFile = await client.open(
      item.sourcePath,
      mode: SftpFileOpenMode.read,
    );

    // Never truncate the user's existing destination while a transfer is in
    // progress. The temporary file is in the same directory so the final
    // rename remains atomic on every platform this app targets.
    final temporaryPath = '${item.destinationPath}.shellvibe-part-$id';
    final tempFile = File(temporaryPath);
    bool committed = false;

    try {
      await tempFile.parent.create(recursive: true);
      final sink = tempFile.openWrite(mode: FileMode.write);

      int transferred = 0;
      int lastTimeMs = stopwatch.elapsedMilliseconds;
      int lastTransferred = 0;
      // The last rate actually measured. Carrying it between samples is what
      // keeps the reported speed steady: re-reading it off the queue item
      // would hand back the value captured when the transfer started, which
      // is always zero, so every chunk between two samples reported 0 B/s.
      int lastSpeed = 0;
      bool sawFirstChunk = false;

      try {
        final stream = remoteFile.read();
        await for (final chunk in stream) {
          if (_cancelFlags[id] == true || _pauseFlags[id] == true) {
            break;
          }
          sink.add(chunk);
          transferred += chunk.length;

          final nowMs = stopwatch.elapsedMilliseconds;
          if (!sawFirstChunk) {
            // Start the window at the first byte that arrived. The time
            // before it is spent opening and stat-ing the remote file, and
            // charging that to the transfer makes the first sample far too
            // slow.
            sawFirstChunk = true;
            lastTimeMs = nowMs;
            lastTransferred = transferred;
          } else if (nowMs - lastTimeMs >= 500) {
            lastSpeed =
                ((transferred - lastTransferred) * 1000) ~/
                (nowMs - lastTimeMs);
            lastTimeMs = nowMs;
            lastTransferred = transferred;
          }

          onProgress(transferred, lastSpeed);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (_cancelFlags[id] != true && _pauseFlags[id] != true) {
        await tempFile.rename(item.destinationPath);
        committed = true;
      }
    } finally {
      await remoteFile.close();
      // Only the temporary file belongs to this transfer. On failure,
      // cancellation, or pause, preserve any pre-existing destination file.
      if (!committed) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _performUpload(
    SftpClient client,
    String id,
    Stopwatch stopwatch,
    void Function(int transferred, int speed) onProgress,
  ) async {
    final item = _queue[id];
    if (item == null) return;
    final localFile = File(item.sourcePath);
    if (!await localFile.exists()) {
      throw Exception('Local file does not exist: ${item.sourcePath}');
    }

    // Never truncate the user's existing destination while a transfer is in
    // progress. The temporary file is in the same directory so the final
    // rename remains atomic on servers implementing normal SFTP rename
    // semantics.
    final temporaryPath = '${item.destinationPath}.shellvibe-part-$id';
    SftpFile? remoteFile;
    remoteFile = await client.open(
      temporaryPath,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );

    bool committed = false;
    try {
      int lastTimeMs = stopwatch.elapsedMilliseconds;
      int lastTransferred = 0;
      // See [_performDownload]: the last measured rate has to survive between
      // samples, otherwise every update in between reports 0 B/s.
      int lastSpeed = 0;
      bool sawFirstAck = false;

      Stream<Uint8List> buildStream() async* {
        await for (final chunk in localFile.openRead()) {
          if (_cancelFlags[id] == true || _pauseFlags[id] == true) {
            break;
          }

          yield chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        }
      }

      // Progress follows the bytes the server has acknowledged, not the bytes
      // read off the local disk. The writer keeps up to a megabyte of requests
      // in flight, so counting local reads measured disk speed instead of the
      // link: short uploads jumped straight to 100% at an absurd rate and then
      // sat there while the pipeline drained.
      await remoteFile.write(
        buildStream(),
        offset: 0,
        onProgress: (transferred) {
          final nowMs = stopwatch.elapsedMilliseconds;
          if (!sawFirstAck) {
            // Start the window at the first acknowledgement: the time before
            // it belongs to opening the remote file, not to the transfer.
            sawFirstAck = true;
            lastTimeMs = nowMs;
            lastTransferred = transferred;
          } else if (nowMs - lastTimeMs >= 500) {
            lastSpeed =
                ((transferred - lastTransferred) * 1000) ~/
                (nowMs - lastTimeMs);
            lastTimeMs = nowMs;
            lastTransferred = transferred;
          }

          onProgress(transferred, lastSpeed);
        },
      );
      await remoteFile.close();
      remoteFile = null;
      if (_cancelFlags[id] != true && _pauseFlags[id] != true) {
        await client.rename(temporaryPath, item.destinationPath);
        committed = true;
      }
    } finally {
      if (remoteFile != null) {
        try {
          await remoteFile.close();
        } catch (_) {}
      }
      // Only the temporary file belongs to this transfer. On failure or
      // cancellation, preserve any pre-existing destination file.
      if (!committed) {
        try {
          await client.remove(temporaryPath);
        } catch (_) {}
      }
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
