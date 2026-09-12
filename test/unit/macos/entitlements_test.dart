@Tags(['macos'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the macOS entitlements against keys that need a signing identity the
/// build may not have.
///
/// This test exists because one of them shipped. `keychain-access-groups` was
/// present as an empty array — granting nothing, since the list was empty — and
/// an empty group list still makes AMFI demand a team identifier. An ad-hoc
/// signature has none, so the kernel killed the app on launch with SIGKILL and
/// no log line. From the outside it looked exactly like Gatekeeper refusing an
/// unsigned build: the user pressed "Open Anyway", nothing happened, and the
/// difference between "blocked" and "killed" is invisible without a shell.
void main() {
  /// Entitlements whose value is a team-scoped identifier. With a Developer ID
  /// they resolve; ad hoc they are fatal. None of them belongs in a build that
  /// has to run both ways.
  const teamScoped = <String>[
    'keychain-access-groups',
    'com.apple.security.application-groups',
    'com.apple.developer.team-identifier',
  ];

  /// Entitlements that only mean something inside the sandbox. The sandbox is
  /// off — Local Shell has to exec a login shell — so these are noise, and it
  /// was noise that hid the fatal key above.
  const sandboxOnly = <String>['com.apple.security.inherit'];

  const files = <String>[
    'macos/Runner/Release.entitlements',
    'macos/Runner/DebugProfile.entitlements',
  ];

  for (final path in files) {
    group(path, () {
      late String source;

      setUpAll(() {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path is missing');
        source = file.readAsStringSync();
      });

      test('declares no team-scoped entitlement', () {
        for (final key in teamScoped) {
          expect(
            source,
            isNot(contains(key)),
            reason:
                '$key needs a team identifier. A Developer ID build supplies '
                'one; an ad-hoc build does not, and AMFI answers with SIGKILL '
                'rather than an error.',
          );
        }
      });

      test('declares no sandbox-only entitlement while the sandbox is off', () {
        expect(source, contains('com.apple.security.app-sandbox'));
        final sandboxOff = RegExp(
          r'<key>com\.apple\.security\.app-sandbox</key>\s*<false\s*/>',
        ).hasMatch(source);
        expect(sandboxOff, isTrue, reason: 'the sandbox is expected to be off');

        for (final key in sandboxOnly) {
          expect(source, isNot(contains(key)));
        }
      });

      test('still grants the network access the app cannot work without', () {
        // SSH, SFTP and the update check are outbound; Device Link listens.
        expect(source, contains('com.apple.security.network.client'));
        expect(source, contains('com.apple.security.network.server'));
      });
    });
  }
}
