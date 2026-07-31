enum TransferType { upload, download }

enum TransferStatus { pending, inProgress, paused, completed, failed, cancelled }

class TransferItem {
  final String id;
  final String fileName;
  final String sourcePath;
  final String destinationPath;
  final int totalBytes;
  final int transferredBytes;
  final TransferStatus status;
  final TransferType type;
  final int speedBytesPerSec;
  final String? error;

  const TransferItem({
    required this.id,
    required this.fileName,
    required this.sourcePath,
    required this.destinationPath,
    required this.totalBytes,
    this.transferredBytes = 0,
    this.status = TransferStatus.pending,
    required this.type,
    this.speedBytesPerSec = 0,
    this.error,
  });

  double get progress => totalBytes > 0 ? (transferredBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  String get formattedSpeed {
    if (speedBytesPerSec <= 0) return '0 B/s';
    if (speedBytesPerSec < 1024) return '$speedBytesPerSec B/s';
    if (speedBytesPerSec < 1024 * 1024) return '${(speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  TransferItem copyWith({
    String? id,
    String? fileName,
    String? sourcePath,
    String? destinationPath,
    int? totalBytes,
    int? transferredBytes,
    TransferStatus? status,
    TransferType? type,
    int? speedBytesPerSec,
    String? error,
  }) {
    return TransferItem(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      sourcePath: sourcePath ?? this.sourcePath,
      destinationPath: destinationPath ?? this.destinationPath,
      totalBytes: totalBytes ?? this.totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      status: status ?? this.status,
      type: type ?? this.type,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      error: error ?? this.error,
    );
  }
}
