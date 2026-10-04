import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';

void main() {
  tearDown(() => debugWindowsStorePackageOverride = null);

  test('only Windows can be the Store package', () {
    // The test host is never a packaged Windows app.
    expect(isWindowsStorePackage, isFalse);
  }, skip: Platform.isWindows ? 'reads the real identity on Windows' : false);

  test('the override stands in for the package identity', () {
    debugWindowsStorePackageOverride = true;
    expect(isWindowsStorePackage, isTrue);
  });
}
