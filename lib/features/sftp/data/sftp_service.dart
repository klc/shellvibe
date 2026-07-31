import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../domain/models/sftp_file_item.dart';

/// Wrapper service over [SftpClient] providing high-level file system operations.
class SftpService {
  /// Default limit for loading an entire file into memory (10 MB).
  static const int defaultMaxReadFileSizeBytes = 10 * 1024 * 1024;

  /// List items in a remote directory
  Future<List<SftpFileItem>> listDirectory(SftpClient client, String path) async {
    final sftpNames = <SftpName>[];
    await for (final chunk in client.readdir(path)) {
      sftpNames.addAll(chunk);
    }

    // Exclude '.' and '..' entries
    final filtered = sftpNames.where(
      (item) => item.filename != '.' && item.filename != '..',
    );

    final items = filtered.map((item) => SftpFileItem.fromSftpName(item, path)).toList();

    // Sort: Directories first, then files alphabetically
    items.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return items;
  }

  /// Stream remote file content in chunks to prevent loading large files into RAM.
  Stream<Uint8List> readFileStream(
    SftpClient client,
    String path, {
    int offset = 0,
    int? length,
  }) async* {
    final file = await client.open(path, mode: SftpFileOpenMode.read);
    try {
      final stream = file.read(offset: offset, length: length);
      await for (final chunk in stream) {
        yield chunk;
      }
    } finally {
      await file.close();
    }
  }

  /// Read remote file content into bytes with an OOM protection limit.
  Future<Uint8List> readFile(
    SftpClient client,
    String path, {
    int maxSizeBytes = defaultMaxReadFileSizeBytes,
  }) async {
    try {
      final stat = await client.stat(path);
      if (stat.size != null && stat.size! > maxSizeBytes) {
        final sizeMb = (stat.size! / (1024 * 1024)).toStringAsFixed(2);
        final limitMb = (maxSizeBytes / (1024 * 1024)).toStringAsFixed(2);
        throw Exception(
          'File size ($sizeMb MB) exceeds maximum in-memory limit ($limitMb MB). '
          'Use readFileStream or downloadToFile to avoid memory exhaustion (OOM).',
        );
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('Use readFileStream or downloadToFile')) {
        rethrow;
      }
      // Stat check failed or unsupported by remote SFTP server; fallback to chunk-level limit check below.
    }

    final file = await client.open(path, mode: SftpFileOpenMode.read);
    try {
      final builder = BytesBuilder();
      final stream = file.read();
      await for (final chunk in stream) {
        builder.add(chunk);
        if (builder.length > maxSizeBytes) {
          final limitMb = (maxSizeBytes / (1024 * 1024)).toStringAsFixed(2);
          throw Exception(
            'File content read exceeded maximum in-memory limit ($limitMb MB). '
            'Use readFileStream or downloadToFile to avoid memory exhaustion (OOM).',
          );
        }
      }
      return builder.takeBytes();
    } finally {
      await file.close();
    }
  }

  /// Download remote file directly to a local file path to prevent high RAM usage.
  Future<void> downloadToFile(
    SftpClient client,
    String remotePath,
    String localPath, {
    void Function(int count, int total)? onProgress,
  }) async {
    int total = 0;
    try {
      final stat = await client.stat(remotePath);
      total = stat.size ?? 0;
    } catch (_) {
      // Stat failed or unsupported; proceed with total = 0
    }

    final localFile = File(localPath);
    final sink = localFile.openWrite();
    int count = 0;

    try {
      await for (final chunk in readFileStream(client, remotePath)) {
        sink.add(chunk);
        count += chunk.length;
        if (onProgress != null) {
          onProgress(count, total > 0 ? total : count);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  /// Write byte content to remote file
  Future<void> writeFile(
    SftpClient client,
    String path,
    Uint8List content, {
    void Function(int count, int total)? onProgress,
  }) async {
    final file = await client.open(
      path,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
    );
    try {
      const chunkSize = 32 * 1024; // 32 KB chunks
      int written = 0;
      final total = content.length;

      while (written < total) {
        final end = (written + chunkSize < total) ? written + chunkSize : total;
        final chunk = content.sublist(written, end);
        await file.write(Stream.value(chunk), offset: written);
        written = end;
        if (onProgress != null) {
          onProgress(written, total);
        }
      }
    } finally {
      await file.close();
    }
  }

  /// Create remote directory
  Future<void> createDirectory(SftpClient client, String path) async {
    await client.mkdir(path);
  }

  /// Create empty remote file
  Future<void> createFile(SftpClient client, String path) async {
    final file = await client.open(
      path,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write,
    );
    await file.close();
  }

  /// Delete remote file or directory
  Future<void> deleteItem(SftpClient client, String path, {required bool isDirectory}) async {
    if (isDirectory) {
      await client.rmdir(path);
    } else {
      await client.remove(path);
    }
  }

  /// Rename or move remote file/directory
  Future<void> renameItem(SftpClient client, String oldPath, String newPath) async {
    await client.rename(oldPath, newPath);
  }

  /// Change file/directory permissions
  Future<void> changePermissions(SftpClient client, String path, int permissions) async {
    final attr = SftpFileAttrs(mode: SftpFileMode.value(permissions));
    await client.setStat(path, attr);
  }

  /// Change file owner / group IDs
  Future<void> changeOwner(SftpClient client, String path, {int? uid, int? gid}) async {
    final attr = SftpFileAttrs(
      userID: uid,
      groupID: gid,
    );
    await client.setStat(path, attr);
  }
}
