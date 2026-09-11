import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/utils/platform_capabilities.dart';

/// Extension used for exported zero-knowledge backup packages. The payload is
/// JSON, so the double extension keeps it openable by any text/JSON tool while
/// still being recognisable in a file listing.
const String kBackupFileExtension = 'shellvibebak.json';

/// File picker/writer for encrypted backup packages.
///
/// Desktop gets the native save dialog; mobile has no save dialog in
/// `file_selector`, so the file is written into the app documents directory
/// and the caller reports the path.
class BackupFileService {
  const BackupFileService();

  static const XTypeGroup _backupTypeGroup = XTypeGroup(
    label: 'ShellVibe backup',
    extensions: <String>['json'],
    uniformTypeIdentifiers: <String>['public.json'],
    mimeTypes: <String>['application/json'],
  );

  /// Writes [backupJson] to a user-chosen location (desktop) or the app
  /// documents directory (mobile). Returns the written path, or null when the
  /// user cancelled the save dialog.
  Future<String?> saveBackup(String backupJson) async {
    final bytes = utf8.encode(backupJson);
    final suggestedName = defaultBackupFileName();

    if (isMobilePlatform) {
      final dir = await getApplicationDocumentsDirectory();
      final path = p.join(dir.path, suggestedName);
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    }

    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const <XTypeGroup>[_backupTypeGroup],
    );
    if (location == null) return null;

    final file = XFile.fromData(
      bytes,
      name: suggestedName,
      mimeType: 'application/json',
    );
    await file.saveTo(location.path);
    return location.path;
  }

  /// Picks a backup file and returns its contents, or null when cancelled.
  Future<PickedBackup?> pickBackup() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_backupTypeGroup],
    );
    if (file == null) return null;
    final contents = await file.readAsString();
    return PickedBackup(name: file.name, contents: contents);
  }

  /// `shellvibe-backup-20260810-142530.shellvibebak.json`
  static String defaultBackupFileName([DateTime? now]) {
    final stamp = (now ?? DateTime.now()).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${stamp.year}${two(stamp.month)}${two(stamp.day)}';
    final time = '${two(stamp.hour)}${two(stamp.minute)}${two(stamp.second)}';
    return 'shellvibe-backup-$date-$time.$kBackupFileExtension';
  }
}

/// A backup file the user selected for import.
class PickedBackup {
  const PickedBackup({required this.name, required this.contents});

  final String name;
  final String contents;
}

final backupFileServiceProvider = Provider<BackupFileService>(
  (ref) => const BackupFileService(),
);
