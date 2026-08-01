import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS declares Face ID usage before local_auth can request it', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(infoPlist, contains('<key>NSFaceIDUsageDescription</key>'));
  });
}
