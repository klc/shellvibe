@Tags(['integration'])
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// Writes to the real keychain on the real platform.
///
/// It goes through [FlutterSecureStorage] directly, with the options
/// [SecureStorageService] would have used, rather than through the service
/// itself. The service catches an entitlement failure outside release mode and
/// answers from an in-memory map — deliberately, so a misprovisioned developer
/// build stays usable — and a test written against it therefore passes while
/// the keychain is never touched. That is not a hypothetical: the first version
/// of this test did exactly that and reported success against a build that
/// could not store a secret at all.
///
/// The failure this exists for shipped in 1.0.0: errSecMissingEntitlement
/// (-34018) on every write, which a user met as "Save Identity Error" the first
/// time they saved an SSH key.
///
/// It reproduces that failure only when the build under test is ad-hoc signed,
/// which is what CI produces and what a checkout with no `DEVELOPMENT_TEAM`
/// gets. On a machine with `Runner/Configs/LocalSigning.xcconfig` naming a
/// team, the binary carries a team identifier, the data protection keychain
/// opens, and this suite stays green with the bug present. Both halves were
/// checked by hand: team aside, the option back to true, -34018 on every
/// write; option false, green.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final storage = FlutterSecureStorage(
    mOptions: SecureStorageService.macOsOptions,
    iOptions: SecureStorageService.iosOptions,
    aOptions: SecureStorageService.androidOptions,
  );

  test('a secret survives a write and a read', () async {
    const key = 'shellvibe_integration_probe';
    final value = 'probe-${DateTime.now().microsecondsSinceEpoch}';

    await storage.write(key: key, value: value);
    addTearDown(() => storage.delete(key: key));

    expect(
      await storage.read(key: key),
      value,
      reason: 'the platform store returned something other than what went in',
    );
  });

  test('a deleted secret is gone', () async {
    const key = 'shellvibe_integration_probe_delete';

    await storage.write(key: key, value: 'x');
    await storage.delete(key: key);

    expect(await storage.read(key: key), isNull);
  });
}
