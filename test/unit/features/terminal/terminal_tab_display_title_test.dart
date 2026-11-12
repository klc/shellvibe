import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:xterm3/xterm.dart';

TerminalTabSession _tab() => TerminalTabSession(
  id: 't',
  title: 'prod-web-01',
  sessionType: TerminalSessionType.ssh,
  terminal: Terminal(),
);

void main() {
  group('displayTitle', () {
    test('falls back to the name the tab was opened with', () {
      expect(_tab().displayTitle, 'prod-web-01');
    });

    test('a reported directory names the tab by its last segment', () {
      final tab = _tab()..workingDirectory = '/var/www/app';
      expect(tab.displayTitle, 'app');
    });

    test('a reported title wins over the directory', () {
      final tab = _tab()
        ..workingDirectory = '/var/www/app'
        ..reportedTitle = 'vim config.yaml';
      expect(tab.displayTitle, 'vim config.yaml');
    });

    test('a blank reported title does not blank the tab', () {
      final tab = _tab()..reportedTitle = '   ';
      expect(tab.displayTitle, 'prod-web-01');
    });
  });

  group('reportedPath', () {
    test('reads the path out of an OSC 7 file URI', () {
      expect(
        TerminalTabSession.reportedPath('file://box/var/log/nginx'),
        '/var/log/nginx',
      );
    });

    test('decodes escapes and drops a trailing slash', () {
      expect(
        TerminalTabSession.reportedPath('file://box/srv/my%20app/'),
        '/srv/my app',
      );
    });

    test('writes the home directory as ~', () {
      expect(
        TerminalTabSession.reportedPath(
          'file://mac/Users/me',
          home: '/Users/me',
        ),
        '~',
      );
      expect(
        TerminalTabSession.reportedPath(
          'file://mac/Users/me/src/app',
          home: '/Users/me',
        ),
        '~/src/app',
      );
      // A sibling that only shares the prefix is not inside home.
      expect(
        TerminalTabSession.reportedPath(
          'file://mac/Users/me2',
          home: '/Users/me',
        ),
        '/Users/me2',
      );
    });
  });

  test('directoryLabel keeps ~ and / as they are', () {
    expect(TerminalTabSession.directoryLabel('~'), '~');
    expect(TerminalTabSession.directoryLabel('/'), '/');
    expect(TerminalTabSession.directoryLabel('~/src/app'), 'app');
  });
}
