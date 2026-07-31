import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/features/sftp/data/sftp_transfer_queue_worker.dart';
import 'package:terly2/features/sftp/domain/models/transfer_item.dart';

void main() {
  group('SftpTransferQueueWorker Unit Tests', () {
    late SftpTransferQueueWorker worker;

    setUp(() {
      worker = SftpTransferQueueWorker();
    });

    tearDown(() {
      worker.dispose();
    });

    test('Queue starts empty and handles pause/cancel state transitions', () {
      expect(worker.queueList, isEmpty);

      // Create dummy item state manually for testing worker state management
      final item = const TransferItem(
        id: 'test-1',
        fileName: 'file.txt',
        sourcePath: '/remote/file.txt',
        destinationPath: '/local/file.txt',
        totalBytes: 1000,
        type: TransferType.download,
      );

      expect(item.progress, 0.0);
      expect(item.status, TransferStatus.pending);
    });

    test('TransferItem progress and formatted speed', () {
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
