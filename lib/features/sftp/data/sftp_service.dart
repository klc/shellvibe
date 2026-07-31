import 'dart:async';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../domain/models/sftp_file_item.dart';

/// Wrapper service over [SftpClient] providing high-level file system operations.
class SftpService {
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

  /// Read remote file content into bytes
  Future<Uint8List> readFile(SftpClient client, String path) async {
    final file = await client.open(path, mode: SftpFileOpenMode.read);
    try {
      final builder = BytesBuilder();
      final stream = file.read();
      await for (final chunk in stream) {
        builder.add(chunk);
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
    final attr = SftpFileAttrs(mode: SftpFileMode());
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
