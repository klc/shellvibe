import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/features/sftp/presentation/providers/sftp_providers.dart';

void main() {
  group('remote SFTP path safety', () {
    test(
      'accepts one filename segment and always joins with POSIX separators',
      () {
        expect(isSafeRemoteName('report.txt'), isTrue);
        expect(
          buildSafeRemoteChildPath('/var/tmp', 'report.txt'),
          '/var/tmp/report.txt',
        );
      },
    );

    test('rejects traversal, absolute paths, separators and NUL bytes', () {
      for (final name in [
        '.',
        '..',
        '../escape',
        r'..\escape',
        '/etc/passwd',
        'a/b',
        'a\\b',
        'bad\u0000name',
      ]) {
        expect(isSafeRemoteName(name), isFalse, reason: name);
        expect(
          () => buildSafeRemoteChildPath('/var/tmp', name),
          throwsA(isA<FormatException>()),
          reason: name,
        );
      }
    });
  });
}
