import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/sftp/data/sftp_transfer_queue_worker.dart';
import 'package:shellvibe/features/sftp/domain/models/transfer_item.dart';

/// A remote file whose bytes the test hands over one chunk at a time, so a
/// transfer can be caught in the middle.
class _ControlledFile implements SftpFile {
  final StreamController<Uint8List> bytes = StreamController<Uint8List>();

  @override
  bool isClosed = false;

  void send(List<int> chunk) => bytes.add(Uint8List.fromList(chunk));

  @override
  Stream<Uint8List> read({
    int? length,
    int offset = 0,
    void Function(int bytesRead)? onProgress,
    int chunkSize = 32768,
    int maxPendingRequests = 10,
  }) => bytes.stream;

  @override
  Future<void> close() async => isClosed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Hands out a fresh [_ControlledFile] for every open, and remembers each one
/// under the path it was opened for.
class _FakeSftpClient implements SftpClient {
  final Map<String, List<_ControlledFile>> opened = {};

  int get openCount =>
      opened.values.fold(0, (sum, files) => sum + files.length);

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    final file = _ControlledFile();
    opened.putIfAbsent(path, () => []).add(file);
    return file;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Polls [condition] until it holds. The worker writes real files, and file
/// I/O completes on the event loop at its own pace, not on a microtask.
Future<void> _eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not reached within 5 seconds');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late SftpTransferQueueWorker worker;
  late _FakeSftpClient client;
  late Directory dir;

  setUp(() async {
    worker = SftpTransferQueueWorker();
    client = _FakeSftpClient();
    dir = await Directory.systemTemp.createTemp('sftp_queue_test');
  });

  tearDown(() async {
    worker.dispose();
    await dir.delete(recursive: true);
  });

  TransferItem item(String id) =>
      worker.queueList.firstWhere((i) => i.id == id);

  /// Leftover `.shellvibe-part-*` files, which only a finished or abandoned
  /// transfer is allowed to have cleaned up.
  List<String> partials() => dir
      .listSync()
      .map((e) => e.path)
      .where((p) => p.contains('.shellvibe-part-'))
      .toList();

  String download(String name) => worker.enqueueDownload(
    client: client,
    remotePath: '/remote/$name',
    localPath: '${dir.path}/$name',
    size: 6,
  );

  test(
    'a finished download lands at its destination and nowhere else',
    () async {
      final id = download('file.bin');
      await _eventually(() => client.opened['/remote/file.bin'] != null);

      final remote = client.opened['/remote/file.bin']!.single;
      remote
        ..send([1, 2, 3])
        ..send([4, 5, 6]);
      await remote.bytes.close();

      await _eventually(() => item(id).status == TransferStatus.completed);
      expect(await File('${dir.path}/file.bin').readAsBytes(), [
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      expect(item(id).transferredBytes, 6);
      expect(partials(), isEmpty);
      expect(remote.isClosed, isTrue);
    },
  );

  test('cancelling leaves the file that was already there untouched', () async {
    final destination = File('${dir.path}/file.bin');
    await destination.writeAsString('original');

    final id = download('file.bin');
    await _eventually(() => client.opened['/remote/file.bin'] != null);
    final remote = client.opened['/remote/file.bin']!.single;

    remote.send([1, 2, 3]);
    await _eventually(() => item(id).transferredBytes == 3);

    worker.cancelTransfer(id);
    remote.send([4, 5, 6]);
    await remote.bytes.close();

    await _eventually(() => remote.isClosed && partials().isEmpty);
    expect(item(id).status, TransferStatus.cancelled);
    expect(await destination.readAsString(), 'original');
  });

  test(
    'runs at most three transfers and starts the next when one ends',
    () async {
      final ids = [
        for (final name in ['a', 'b', 'c', 'd']) download(name),
      ];
      await _eventually(() => client.openCount == 3);

      // The fourth is waiting for a slot, not failed or dropped.
      await pumpEventQueue();
      expect(client.opened['/remote/d'], isNull);
      expect(item(ids[3]).status, TransferStatus.pending);

      final first = client.opened['/remote/a']!.single;
      first.send([1, 2, 3, 4, 5, 6]);
      await first.bytes.close();

      await _eventually(() => client.opened['/remote/d'] != null);
      expect(item(ids[0]).status, TransferStatus.completed);
    },
  );

  test(
    'resuming while the paused run is still unwinding restarts it once',
    () async {
      final id = download('file.bin');
      await _eventually(() => client.opened['/remote/file.bin'] != null);
      final firstRun = client.opened['/remote/file.bin']!.single;

      firstRun.send([1, 2, 3]);
      await _eventually(() => item(id).transferredBytes == 3);

      // The paused loop only notices on its next chunk, so the resume lands
      // while the first run still holds the transfer. Starting a second run
      // here would have two writers on one destination.
      worker.pauseTransfer(id);
      worker.resumeTransfer(client, id);
      await pumpEventQueue();
      expect(client.opened['/remote/file.bin'], hasLength(1));

      firstRun.send([9, 9, 9]);
      await _eventually(() => client.opened['/remote/file.bin']!.length == 2);

      final secondRun = client.opened['/remote/file.bin']![1];
      secondRun.send([1, 2, 3, 4, 5, 6]);
      await secondRun.bytes.close();
      await firstRun.bytes.close();

      await _eventually(() => item(id).status == TransferStatus.completed);
      expect(await File('${dir.path}/file.bin').readAsBytes(), [
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      expect(client.opened['/remote/file.bin'], hasLength(2));
      expect(partials(), isEmpty);
    },
  );

  test('clearFinished drops completed and cancelled rows only', () async {
    final done = download('done.bin');
    final cancelled = download('cancelled.bin');
    final running = download('running.bin');
    await _eventually(() => client.openCount == 3);

    final doneFile = client.opened['/remote/done.bin']!.single;
    doneFile.send([1, 2, 3, 4, 5, 6]);
    await doneFile.bytes.close();
    worker.cancelTransfer(cancelled);
    final cancelledFile = client.opened['/remote/cancelled.bin']!.single;
    await cancelledFile.bytes.close();

    await _eventually(
      () =>
          item(done).status == TransferStatus.completed &&
          cancelledFile.isClosed,
    );
    await pumpEventQueue();
    worker.clearFinished();

    expect(worker.queueList.map((i) => i.id), [running]);
  });

  group('TransferItem', () {
    test('reports progress and a human readable speed', () {
      const item = TransferItem(
        id: 't-1',
        fileName: 'app.iso',
        sourcePath: '/a',
        destinationPath: '/b',
        totalBytes: 100,
        transferredBytes: 50,
        type: TransferType.download,
        speedBytesPerSec: 2048576,
      );

      expect(item.progress, 0.5);
      expect(item.formattedSpeed, '2.0 MB/s');
    });
  });
}
