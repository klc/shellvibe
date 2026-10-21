import 'dart:async';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../domain/models/sftp_file_item.dart';

/// Wrapper service over [SftpClient] providing high-level file system operations.
class SftpService {
  /// Default limit for loading an entire file into memory (10 MB).
  static const int defaultMaxReadFileSizeBytes = 10 * 1024 * 1024;

  /// List items in a remote directory
  Future<List<SftpFileItem>> listDirectory(
    SftpClient client,
    String path,
  ) async {
    final sftpNames = <SftpName>[];
    await for (final chunk in client.readdir(path)) {
      sftpNames.addAll(chunk);
    }

    // Exclude '.' and '..' entries, and mitigate path traversal (slip attacks)
    final filtered = sftpNames.where((item) {
      final name = item.filename;
      if (name == '.' || name == '..') return false;
      // Mitigate path traversal attacks from malicious servers
      if (name.contains('/') || name.contains('\\')) return false;
      return true;
    });

    final items = filtered
        .map((item) => SftpFileItem.fromSftpName(item, path))
        .toList();

    // readdir attributes do not follow links: ask where a symlink leads.
    // ponytail: one stat per symlink, in order; batch if a folder has many.
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (!item.isSymlink || item.isDirectory) continue;
      try {
        final target = await client.stat(item.path);
        if (target.isDirectory) items[i] = item.copyWith(isDirectory: true);
      } catch (_) {
        // Dangling or unreadable link: leave it as a file.
      }
    }

    // Sort: Directories first, then files alphabetically
    items.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return items;
  }

  /// Read remote file content into bytes with an OOM protection limit.
  Future<Uint8List> readFile(
    SftpClient client,
    String path, {
    int maxSizeBytes = defaultMaxReadFileSizeBytes,
  }) async {
    final limitMb = (maxSizeBytes / (1024 * 1024)).toStringAsFixed(2);

    int? statedSize;
    try {
      statedSize = (await client.stat(path)).size;
    } catch (_) {
      // Stat failed or unsupported by the remote SFTP server; the chunk-level
      // check below still bounds memory.
    }
    if (statedSize != null && statedSize > maxSizeBytes) {
      final sizeMb = (statedSize / (1024 * 1024)).toStringAsFixed(2);
      throw Exception(
        'File size ($sizeMb MB) exceeds maximum in-memory limit ($limitMb MB).',
      );
    }

    final file = await client.open(path, mode: SftpFileOpenMode.read);
    try {
      final builder = BytesBuilder();
      await for (final chunk in file.read()) {
        builder.add(chunk);
        if (builder.length > maxSizeBytes) {
          throw Exception(
            'File content read exceeded maximum in-memory limit ($limitMb MB).',
          );
        }
      }
      return builder.takeBytes();
    } finally {
      await file.close();
    }
  }

  /// Write byte content to remote file
  Future<void> writeFile(
    SftpClient client,
    String path,
    Uint8List content,
  ) async {
    final file = await client.open(
      path,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    try {
      // dartssh2 chunks and pipelines the writes itself.
      await file.write(Stream.value(content));
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
  Future<void> deleteItem(
    SftpClient client,
    String path, {
    required bool isDirectory,
  }) async {
    if (isDirectory) {
      await client.rmdir(path);
    } else {
      await client.remove(path);
    }
  }

  /// Rename or move remote file/directory
  Future<void> renameItem(
    SftpClient client,
    String oldPath,
    String newPath,
  ) async {
    await client.rename(oldPath, newPath);
  }

  /// Change file/directory permissions
  Future<void> changePermissions(
    SftpClient client,
    String path,
    int permissions,
  ) async {
    final attr = SftpFileAttrs(mode: SftpFileMode.value(permissions));
    await client.setStat(path, attr);
  }

  /// Change file owner / group IDs
  Future<void> changeOwner(
    SftpClient client,
    String path, {
    int? uid,
    int? gid,
  }) async {
    final attr = SftpFileAttrs(userID: uid, groupID: gid);
    await client.setStat(path, attr);
  }
}
