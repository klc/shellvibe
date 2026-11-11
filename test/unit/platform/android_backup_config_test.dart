import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android keeps the database out of a device-to-device transfer', () {
    // The transfer would carry the database but not the Keystore key that
    // opens the vault.
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );

    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    final transfer = RegExp(
      r'<device-transfer>(.*?)</device-transfer>',
      dotAll: true,
    ).firstMatch(rules)!.group(1)!;
    for (final domain in ['root', 'file', 'database', 'sharedpref']) {
      expect(transfer, contains('<exclude domain="$domain" path="." />'));
    }
  });
}
