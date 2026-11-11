import 'dart:async';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
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
    final replacement = await openRemoteReplacement(
      client,
      path,
      tempSuffix: const Uuid().v4(),
    );
    try {
      try {
        // dartssh2 chunks and pipelines the writes itself.
        await replacement.file.write(Stream.value(content));
      } finally {
        await replacement.file.close();
      }
      await replacement.commit(client);
    } catch (_) {
      await replacement.discard(client);
      rethrow;
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
      await _removeTree(client, path);
    } else {
      await client.remove(path);
    }
  }

  /// Deletes [path] and everything under it; SFTP's rmdir only takes an
  /// empty directory.
  Future<void> _removeTree(SftpClient client, String path) async {
    // Listed up front: removing entries while the directory handle is still
    // being read may make the server skip some of the rest.
    for (final entry in await client.listdir(path)) {
      final name = entry.filename;
      if (name == '.' || name == '..' || name.contains('/')) continue;
      final child = p.posix.join(path, name);
      // readdir attributes do not follow links: a link to a folder is
      // unlinked, never descended into.
      if (entry.attr.isDirectory) {
        await _removeTree(client, child);
      } else {
        await client.remove(child);
      }
    }
    await client.rmdir(path);
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

/// A write handle that replaces a remote file once [commit]ted.
///
/// Truncating the user's file in place leaves it empty when the connection
/// drops mid-write, so the bytes go to a sibling temp file that is renamed
/// over the original. When that cannot keep the original's owner, [file] is
/// the original itself, opened in place, and [commit]/[discard] do nothing.
class RemoteReplacement {
  RemoteReplacement._(
    this.file,
    this.targetPath, [
    this._temporaryPath,
    this._replacesExisting = false,
  ]);

  /// Where the bytes go.
  final SftpFile file;

  /// The file that ends up with the bytes; a symlink's resolved target.
  final String targetPath;

  final String? _temporaryPath;
  final bool _replacesExisting;
  bool _targetRemoved = false;

  /// Moves the written temp file into place.
  Future<void> commit(SftpClient client) async {
    final temporaryPath = _temporaryPath;
    if (temporaryPath == null) return;
    try {
      await client.rename(temporaryPath, targetPath);
    } catch (_) {
      // Without posix-rename, SFTP's own rename refuses an existing target:
      // make room first. Not atomic, but the only way to overwrite there.
      final extensions = (await client.handshake).extensions;
      if (!_replacesExisting ||
          extensions.containsKey('posix-rename@openssh.com')) {
        rethrow;
      }
      await client.remove(targetPath);
      _targetRemoved = true;
      await client.rename(temporaryPath, targetPath);
    }
  }

  /// Removes the temp file after a failed or abandoned write.
  Future<void> discard(SftpClient client) async {
    final temporaryPath = _temporaryPath;
    // Once the original is gone the temp file is the only copy left.
    if (temporaryPath == null || _targetRemoved) return;
    try {
      await client.remove(temporaryPath);
    } catch (_) {}
  }
}

/// Opens an overwrite of [path] that keeps what the old file had: a symlink
/// stays a link (its target is replaced) and the new file gets the old one's
/// mode and owner. [tempSuffix] makes the temp file name unique.
Future<RemoteReplacement> openRemoteReplacement(
  SftpClient client,
  String path, {
  required String tempSuffix,
}) async {
  final writeMode =
      SftpFileOpenMode.create |
      SftpFileOpenMode.write |
      SftpFileOpenMode.truncate;
  Future<RemoteReplacement> inPlace(String target) async =>
      RemoteReplacement._(await client.open(target, mode: writeMode), target);

  var target = path;
  SftpFileAttrs? existing;
  try {
    existing = await client.stat(path, followLink: false);
  } catch (_) {
    // New file, or stat unsupported: nothing to preserve.
  }
  if (existing != null && existing.isSymbolicLink) {
    // Renaming over the link would turn it into a plain file and leave the
    // file it points to unchanged.
    try {
      target = await client.absolute(path);
    } catch (_) {
      // Unresolvable link: an in-place open follows it.
      return inPlace(path);
    }
    try {
      existing = await client.stat(target);
    } catch (_) {
      existing = null;
    }
  }

  // Same directory as the target, so the rename stays atomic.
  final temporaryPath = '$target.shellvibe-part-$tempSuffix';
  final SftpFile file;
  try {
    file = await client.open(temporaryPath, mode: writeMode);
  } catch (_) {
    // Directory not writable but the file may be.
    return inPlace(target);
  }

  if (existing != null) {
    try {
      // Owner before mode: chown clears the setuid/setgid bits.
      final uid = existing.userID;
      final gid = existing.groupID;
      if (uid != null && gid != null) {
        await client.setStat(
          temporaryPath,
          SftpFileAttrs(userID: uid, groupID: gid),
        );
      }
      final mode = existing.mode?.value;
      if (mode != null) {
        // Permission bits only; the type bits are not setstat's business.
        await client.setStat(
          temporaryPath,
          SftpFileAttrs(mode: SftpFileMode.value(mode & 0xFFF)),
        );
      }
    } catch (_) {
      // Not allowed to hand the file back to its owner (someone else's file,
      // not root): write in place so the owner stays as it was.
      try {
        await file.close();
      } catch (_) {}
      try {
        await client.remove(temporaryPath);
      } catch (_) {}
      return inPlace(target);
    }
  }
  return RemoteReplacement._(file, target, temporaryPath, existing != null);
}
