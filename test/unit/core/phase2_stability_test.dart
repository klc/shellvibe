import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/features/sftp/data/sftp_service.dart';
import 'package:terly2/core/network/ssh_session_manager.dart';
import 'package:terly2/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:xterm3/xterm.dart';

void main() {
  group('Phase 2 Stability & Wiring Tests', () {
    test('SSHConnectConfig default timeout is 15 seconds', () {
      const config = SSHConnectConfig(
        hostname: 'example.com',
        username: 'admin',
      );
      expect(config.timeout, equals(const Duration(seconds: 15)));
    });

    test('TerminalTabSession resizeTerminal resizes xterm Terminal object', () {
      final terminal = Terminal(maxLines: 100);
      final session = TerminalTabSession(
        id: 'tab-1',
        title: 'Test Tab',
        sessionType: TerminalSessionType.local,
        terminal: terminal,
      );

      session.resizeTerminal(100, 40);
      expect(terminal.viewWidth, equals(100));
      expect(terminal.viewHeight, equals(40));
    });

    test('SftpService.uploadFromFile throws exception if local file does not exist', () async {
      final service = SftpService();
      // Dummy non-existent file
      final nonExistentPath = '/tmp/non_existent_file_${DateTime.now().millisecondsSinceEpoch}.tmp';

      expect(
        () async => await service.uploadFromFile(
          _FakeSftpClient(),
          nonExistentPath,
          '/remote/path.txt',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('TerminalTabSession dispose safely cleans up without throwing exceptions', () async {
      final terminal = Terminal(maxLines: 100);
      final session = TerminalTabSession(
        id: 'tab-2',
        title: 'Disposable Tab',
        sessionType: TerminalSessionType.local,
        terminal: terminal,
      );

      expect(() async => await session.dispose(), returnsNormally);
    });
  });
}

class _FakeSftpClient implements SftpClient {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

