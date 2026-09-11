@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/constants/app_constants.dart';

void main() {
  test('AppConstants.appVersion matches pubspec.yaml', () {
    // The release workflow already refuses a tag whose version disagrees with
    // pubspec.yaml and CHANGELOG.md. This constant is the fourth copy of the
    // same number and the workflow does not see it — but the About screen
    // shows it, bug reports quote it, and the update check compares against
    // it, so a stale value here makes the app lie about which build it is.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([^\s+]+)',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml has no version line');
    expect(AppConstants.appVersion, match!.group(1));
  });
}
