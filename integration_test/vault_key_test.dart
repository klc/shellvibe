@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// Exercises the path a user walks when they save an SSH identity.
///
/// [VaultKeyService.getDek] is what the identity form reaches, and what
/// answered errSecMissingEntitlement (-34018) in 1.0.0 — surfacing as the
/// "Save Identity Error" dialog. It takes plain constructor arguments rather
/// than a widget, so the whole chain down to the platform keychain runs here
/// without a tap.
///
/// Run it AOT-compiled and ad-hoc signed to match what ships:
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/vault_key_test.dart -d macos --profile
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('the vault key can be created and read back', () async {
    final service = VaultKeyService(
      encryptionEngine: EncryptionEngine(),
      secureStorageService: SecureStorageService(),
    );

    final dek = await service.getDek();
    final bytes = await dek.extractBytes();
    expect(bytes, isNotEmpty, reason: 'the vault key came back empty');

    // Same key on a second read: it was stored, not regenerated. A key that
    // changes per call would decrypt nothing written before it.
    final again = await VaultKeyService(
      encryptionEngine: EncryptionEngine(),
      secureStorageService: SecureStorageService(),
    ).getDek();
    expect(
      await again.extractBytes(),
      bytes,
      reason: 'the key did not survive being written and read back',
    );
  });
}
