import 'package:flutter_test/flutter_test.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellvibe/features/sftp/presentation/providers/sftp_providers.dart';

class _FakeSftpClient implements SftpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

    test('stale session cleanup cannot clear a newer SFTP client', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sftpProvider.notifier);
      final client = _FakeSftpClient();

      await notifier.setRemoteClient(client, sessionId: 'tab-2');
      await notifier.setRemoteClient(null, sessionId: 'tab-1');

      final state = container.read(sftpProvider);
      expect(state.remoteClient, same(client));
      expect(state.remoteSessionId, equals('tab-2'));

      await notifier.setRemoteClient(null, sessionId: 'tab-2');
      expect(container.read(sftpProvider).remoteClient, isNull);
      expect(container.read(sftpProvider).remoteSessionId, isNull);
    });
  });
}
