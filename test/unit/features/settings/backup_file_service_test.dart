import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/settings/domain/services/backup_file_service.dart';

void main() {
  group('BackupFileService.defaultBackupFileName', () {
    test('is timestamped and carries the backup extension', () {
      final name = BackupFileService.defaultBackupFileName(
        DateTime(2026, 8, 10, 14, 25, 30),
      );

      expect(name, 'shellvibe-backup-20260810-142530.$kBackupFileExtension');
    });

    test('zero-pads single digit date parts', () {
      final name = BackupFileService.defaultBackupFileName(
        DateTime(2026, 1, 2, 3, 4, 5),
      );

      expect(name, 'shellvibe-backup-20260102-030405.$kBackupFileExtension');
    });
  });
}
