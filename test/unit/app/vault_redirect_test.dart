import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/app/router/app_router.dart';
import 'package:terly2/features/vault/presentation/notifiers/vault_notifier.dart';

void main() {
  group('resolveVaultRedirect', () {
    test('sends a locked vault to the unlock screen from anywhere', () {
      expect(resolveVaultRedirect(VaultStatus.locked, '/hosts'),
          equals(kUnlockRoute));
      expect(resolveVaultRedirect(VaultStatus.locked, '/settings'),
          equals(kUnlockRoute));
    });

    test('keeps a locked vault on the unlock screen without looping', () {
      expect(resolveVaultRedirect(VaultStatus.locked, kUnlockRoute), isNull);
    });

    test('stays on the unlock screen while the state is still resolving', () {
      // AsyncLoading is also the state during an unlock attempt: bouncing to
      // /hosts here would abort the password entry mid-verification.
      expect(resolveVaultRedirect(null, kUnlockRoute), isNull);
    });

    test('leaves the unlock screen once unlocked or unconfigured', () {
      expect(resolveVaultRedirect(VaultStatus.unlocked, kUnlockRoute),
          equals('/terminal'));
      expect(resolveVaultRedirect(VaultStatus.unconfigured, kUnlockRoute),
          equals('/terminal'));
    });

    test('does not interfere with normal navigation', () {
      expect(resolveVaultRedirect(VaultStatus.unlocked, '/sftp'), isNull);
      expect(resolveVaultRedirect(VaultStatus.unconfigured, '/hosts'), isNull);
      expect(resolveVaultRedirect(null, '/hosts'), isNull);
    });
  });
}
