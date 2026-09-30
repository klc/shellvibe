import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/window/launch_at_login.dart';
import 'package:shellvibe/app/window/start_hidden.dart';

void main() {
  group('WindowsLaunchAtLogin', () {
    late Map<String, String> run;
    late Map<String, String> approved;
    late List<List<String>> calls;
    late WindowsLaunchAtLogin login;

    const exe = r'C:\Program Files\ShellVibe\shellvibe.exe';
    const runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

    /// A registry that is two maps, driven through the `reg` arguments the
    /// service sends.
    Future<ProcessResult> fakeReg(String executable, List<String> args) async {
      calls.add([executable, ...args]);
      final key = args[1];
      final store = key == runKey ? run : approved;
      final name = args[3];
      switch (args[0]) {
        case 'query':
          final value = store[name];
          if (value == null) return ProcessResult(0, 1, '', 'not found');
          final type = store == run ? 'REG_SZ' : 'REG_BINARY';
          return ProcessResult(
            0,
            0,
            '\r\n$key\r\n    $name    $type    $value\r\n',
            '',
          );
        case 'add':
          store[name] = args[args.indexOf('/d') + 1];
          return ProcessResult(0, 0, '', '');
        case 'delete':
          final had = store.remove(name) != null;
          return ProcessResult(0, had ? 0 : 1, '', '');
      }
      fail('unexpected reg call $args');
    }

    setUp(() {
      run = {};
      approved = {};
      calls = [];
      login = WindowsLaunchAtLogin(executable: exe, run: fakeReg);
    });

    test('registers the quoted path with the hidden argument', () async {
      expect(await login.isEnabled(), isFalse);

      await login.setEnabled(true);

      expect(run['ShellVibe'], '"$exe" $kStartHiddenArgument');
      expect(await login.isEnabled(), isTrue);
    });

    test('turning it off removes the entry', () async {
      await login.setEnabled(true);
      await login.setEnabled(false);

      expect(run, isEmpty);
      expect(await login.isEnabled(), isFalse);
      // Removing what is not there is not an error.
      await login.setEnabled(false);
    });

    test('an entry for another path is not this install', () async {
      run['ShellVibe'] = r'"D:\old\shellvibe.exe" --hidden';
      expect(await login.isEnabled(), isFalse);
    });

    test('an entry the user switched off in Startup Apps is off', () async {
      run['ShellVibe'] = '"$exe" $kStartHiddenArgument';
      approved['ShellVibe'] = '030000000000000000000000';
      expect(await login.isEnabled(), isFalse);

      // Turning it on clears that mark, or it would be registered and idle.
      await login.setEnabled(true);
      expect(approved, isEmpty);
      expect(await login.isEnabled(), isTrue);
    });

    test('an approved entry reads as on', () async {
      run['ShellVibe'] = '"$exe" $kStartHiddenArgument';
      approved['ShellVibe'] = '020000000000000000000000';
      expect(await login.isEnabled(), isTrue);
    });

    test('a failed write is reported', () async {
      final failing = WindowsLaunchAtLogin(
        executable: exe,
        run: (executable, args) async => ProcessResult(0, 5, '', 'denied'),
      );
      await expectLater(
        failing.setEnabled(true),
        throwsA(isA<ProcessException>()),
      );
    });
  });

  group('LinuxLaunchAtLogin', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('autostart'));
    tearDown(() => dir.deleteSync(recursive: true));

    LinuxLaunchAtLogin login({String exe = '/opt/ShellVibe/shellvibe'}) =>
        LinuxLaunchAtLogin(
          executable: exe,
          autostartDirectory: Directory('${dir.path}/autostart'),
        );

    test(
      'writes an autostart entry that starts hidden, and removes it',
      () async {
        final service = login();
        expect(await service.isEnabled(), isFalse);

        await service.setEnabled(true);

        final file = File('${dir.path}/autostart/shellvibe.desktop');
        expect(file.existsSync(), isTrue);
        final text = file.readAsStringSync();
        expect(text, contains('Exec="/opt/ShellVibe/shellvibe" --hidden\n'));
        expect(text, contains('Type=Application'));
        expect(await service.isEnabled(), isTrue);

        await service.setEnabled(false);
        expect(file.existsSync(), isFalse);
        expect(await service.isEnabled(), isFalse);
      },
    );

    test('quotes a path with spaces and reserved characters', () {
      expect(
        login(exe: r'/home/a b/$x/shellvibe').exec,
        r'"/home/a b/\$x/shellvibe" --hidden',
      );
    });

    test('an entry for another executable is not this install', () async {
      await login(exe: '/old/shellvibe').setEnabled(true);
      expect(await login().isEnabled(), isFalse);
    });

    test('an entry disabled by hand with Hidden=true is off', () async {
      final service = login();
      await service.setEnabled(true);
      final file = File('${dir.path}/autostart/shellvibe.desktop');
      file.writeAsStringSync('${file.readAsStringSync()}Hidden=true\n');
      expect(await service.isEnabled(), isFalse);
    });
  });
}
