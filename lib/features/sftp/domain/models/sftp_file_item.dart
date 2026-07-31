import 'dart:io';
import 'package:dartssh2/dartssh2.dart';

/// Represents a file or directory node in local or remote SFTP file system.
class SftpFileItem {
  final String name;
  final String path;
  final int size;
  final String permissions;
  final DateTime? modifyTime;
  final bool isDirectory;
  final bool isSymlink;
  final bool isLocal;
  final int? ownerId;
  final int? groupId;

  const SftpFileItem({
    required this.name,
    required this.path,
    required this.size,
    required this.permissions,
    this.modifyTime,
    required this.isDirectory,
    this.isSymlink = false,
    this.isLocal = false,
    this.ownerId,
    this.groupId,
  });

  /// Factory from dartssh2 [SftpName]
  factory SftpFileItem.fromSftpName(SftpName sftpName, String parentPath) {
    final filename = sftpName.filename;
    final cleanParent = parentPath.endsWith('/') ? parentPath : '$parentPath/';
    final fullPath = parentPath == '/' ? '/$filename' : '$cleanParent$filename';

    final attr = sftpName.attr;
    final isDir = attr.isDirectory;
    final isLink = attr.isSymbolicLink;
    final modeInt = attr.mode?.value ?? 0;
    final permissionsStr = _formatModeToString(modeInt, isDir, isLink);

    return SftpFileItem(
      name: filename,
      path: fullPath,
      size: attr.size ?? 0,
      permissions: permissionsStr,
      modifyTime: attr.modifyTime != null
          ? DateTime.fromMillisecondsSinceEpoch(attr.modifyTime! * 1000)
          : null,
      isDirectory: isDir,
      isSymlink: isLink,
      isLocal: false,
      ownerId: attr.userID,
      groupId: attr.groupID,
    );
  }

  /// Factory from local [FileSystemEntity]
  factory SftpFileItem.fromFileSystemEntity(FileSystemEntity entity, {FileStat? stat}) {
    final name = entity.path.split(Platform.pathSeparator).last;
    final isDir = entity is Directory;
    final isLink = entity is Link;
    final fileStat = stat ?? entity.statSync();

    return SftpFileItem(
      name: name.isEmpty ? entity.path : name,
      path: entity.path,
      size: fileStat.size,
      permissions: _formatModeToString(fileStat.mode, isDir, isLink),
      modifyTime: fileStat.modified,
      isDirectory: isDir,
      isSymlink: isLink,
      isLocal: true,
    );
  }

  /// Format file size into human-readable string (e.g. 1.5 MB).
  String get formattedSize {
    if (isDirectory) return '--';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Octal permission string (e.g. "755", "644")
  String get octalPermissions {
    final permBits = _extractOctalFromPermission(permissions);
    return permBits;
  }

  static String _extractOctalFromPermission(String permStr) {
    if (permStr.length < 9) return '755';
    final str = permStr.startsWith('d') || permStr.startsWith('l') || permStr.startsWith('-')
        ? permStr.substring(1)
        : permStr;
    
    int u = 0, g = 0, o = 0;
    if (str.length >= 9) {
      if (str[0] == 'r') u += 4;
      if (str[1] == 'w') u += 2;
      if (str[2] == 'x') u += 1;
      if (str[3] == 'r') g += 4;
      if (str[4] == 'w') g += 2;
      if (str[5] == 'x') g += 1;
      if (str[6] == 'r') o += 4;
      if (str[7] == 'w') o += 2;
      if (str[8] == 'x') o += 1;
    }
    return '$u$g$o';
  }

  static String _formatModeToString(int mode, bool isDir, bool isLink) {
    final typeChar = isDir ? 'd' : (isLink ? 'l' : '-');
    final uR = (mode & 0x0100) != 0 ? 'r' : '-';
    final uW = (mode & 0x0080) != 0 ? 'w' : '-';
    final uX = (mode & 0x0040) != 0 ? 'x' : '-';
    final gR = (mode & 0x0020) != 0 ? 'r' : '-';
    final gW = (mode & 0x0010) != 0 ? 'w' : '-';
    final gX = (mode & 0x0008) != 0 ? 'x' : '-';
    final oR = (mode & 0x0004) != 0 ? 'r' : '-';
    final oW = (mode & 0x0002) != 0 ? 'w' : '-';
    final oX = (mode & 0x0001) != 0 ? 'x' : '-';

    return '$typeChar$uR$uW$uX$gR$gW$gX$oR$oW$oX';
  }

  SftpFileItem copyWith({
    String? name,
    String? path,
    int? size,
    String? permissions,
    DateTime? modifyTime,
    bool? isDirectory,
    bool? isSymlink,
    bool? isLocal,
    int? ownerId,
    int? groupId,
  }) {
    return SftpFileItem(
      name: name ?? this.name,
      path: path ?? this.path,
      size: size ?? this.size,
      permissions: permissions ?? this.permissions,
      modifyTime: modifyTime ?? this.modifyTime,
      isDirectory: isDirectory ?? this.isDirectory,
      isSymlink: isSymlink ?? this.isSymlink,
      isLocal: isLocal ?? this.isLocal,
      ownerId: ownerId ?? this.ownerId,
      groupId: groupId ?? this.groupId,
    );
  }
}
