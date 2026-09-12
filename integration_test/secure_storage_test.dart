@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// Writes to the real keychain on the real platform.
///
/// A Dart VM test reaches no keychain at all, so this is the only level at
/// which "can the app store a secret" is a question with an answer.
///
/// **What it does not cover.** The 1.0.0 failure — errSecMissingEntitlement
/// (-34018) on every write, surfacing as "Save Identity Error" the first time
/// a user added an SSH key — needed the data protection keychain *and* a
/// binary with no team identifier. `flutter test` builds debug and signs it
/// with a development certificate, which has one, so that combination cannot
/// be reproduced here; flipping usesDataProtectionKeychain back to true leaves
/// this suite green. Verified by doing exactly that.
///
/// So this catches a keychain that is broken outright, not that specific
/// interaction. The guard for that one is the entitlements test beside it, and
/// opening the packaged unsigned build by hand before a release.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('a secret survives a write and a read', () async {
    final storage = SecureStorageService();
    const key = 'shellvibe_integration_probe';
    final value = 'probe-${DateTime.now().microsecondsSinceEpoch}';

    await storage.write(key: key, value: value);
    addTearDown(() => storage.delete(key: key));

    expect(
      await storage.read(key: key),
      value,
      reason: 'the keychain returned something other than what was stored',
    );
  });

  test('a deleted secret is gone', () async {
    final storage = SecureStorageService();
    const key = 'shellvibe_integration_probe_delete';

    await storage.write(key: key, value: 'x');
    await storage.delete(key: key);

    expect(await storage.read(key: key), isNull);
  });
}
