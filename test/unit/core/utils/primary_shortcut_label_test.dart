import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';

void main() {
  tearDown(() => debugPlatformCapabilitiesOverride = null);

  test('Command on Apple keyboards', () {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
      debugPlatformCapabilitiesOverride = platform;
      expect(primaryShortcutLabel('K'), '⌘K', reason: '$platform');
    }
  });

  test('Ctrl everywhere else', () {
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.android,
    ]) {
      debugPlatformCapabilitiesOverride = platform;
      expect(primaryShortcutLabel('K'), 'Ctrl+K', reason: '$platform');
    }
  });
}
