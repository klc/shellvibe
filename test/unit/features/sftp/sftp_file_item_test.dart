import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/sftp/domain/models/sftp_file_item.dart';

void main() {
  group('SftpFileItem Unit Tests', () {
    test('formattedSize calculates human readable sizes correctly', () {
      const itemBytes = SftpFileItem(
        name: 'test.txt',
        path: '/test.txt',
        size: 500,
        permissions: '-rw-r--r--',
        isDirectory: false,
      );
      expect(itemBytes.formattedSize, '500 B');

      const itemKb = SftpFileItem(
        name: 'test.txt',
        path: '/test.txt',
        size: 2048,
        permissions: '-rw-r--r--',
        isDirectory: false,
      );
      expect(itemKb.formattedSize, '2.0 KB');

      const itemMb = SftpFileItem(
        name: 'test.txt',
        path: '/test.txt',
        size: 10485760,
        permissions: '-rw-r--r--',
        isDirectory: false,
      );
      expect(itemMb.formattedSize, '10.0 MB');

      const itemDir = SftpFileItem(
        name: 'folder',
        path: '/folder',
        size: 4096,
        permissions: 'drwxr-xr-x',
        isDirectory: true,
      );
      expect(itemDir.formattedSize, '--');
    });
  });
}
