// Branches on the host OS, so CI runs it on macOS and Windows as well as
// Linux on every pull request (`--tags platform`).
@Tags(['platform'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/core/network/local_pty_manager.dart';

void main() {
  final manager = LocalPtyManager();

  group('LocalPtyManager.defaultShellArguments', () {
    test('starts known POSIX shells as login shells', () {
      // A GUI app inherits launchd's minimal PATH; only a login shell reads
      // the user's profile and gets Homebrew binaries back on PATH.
      for (final shell in ['/bin/zsh', '/bin/bash', '/bin/sh', '/usr/bin/fish',
        '/usr/local/bin/dash', '/bin/tcsh']) {
        expect(
          manager.defaultShellArguments(shell),
          ['-l'],
          reason: '$shell should be started as a login shell',
        );
      }
    }, skip: Platform.isWindows);

    test('starts shells that may not understand -l bare', () {
      // `Pty.start` forks and execs, so a rejected flag is not an exception we
      // could catch and retry — the child just dies. Anything not known to
      // take `-l` gets a bare invocation instead of a dead pane.
      for (final shell in [
        '/opt/homebrew/bin/nu',
        '/usr/local/bin/elvish',
        '/usr/bin/rbash',
        '/some/wrapper',
      ]) {
        expect(
          manager.defaultShellArguments(shell),
          isEmpty,
          reason: '$shell is not known to accept -l',
        );
      }
    }, skip: Platform.isWindows);

    test('never adds a login flag on Windows', () {
      expect(manager.defaultShellArguments('powershell.exe'), isEmpty);
    }, skip: !Platform.isWindows);
  });
}
