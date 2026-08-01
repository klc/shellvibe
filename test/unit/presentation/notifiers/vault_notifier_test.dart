import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:terly2/core/crypto/encryption_engine.dart';
import 'package:terly2/shared/providers/database_providers.dart';
import 'package:terly2/features/vault/presentation/notifiers/identities_notifier.dart';
import 'package:terly2/features/vault/presentation/notifiers/vault_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fastEngine = EncryptionEngine(
    kdf: Argon2id(parallelism: 1, memory: 8, iterations: 1, hashLength: 32),
  );

  group('VaultNotifier State Transition Unit Tests', () {
    late ProviderContainer container;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      container = ProviderContainer(
        overrides: [encryptionEngineProvider.overrideWithValue(fastEngine)],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test(
      'Initial state is unconfigured when no master key exists in storage',
      () async {
        final state = await container.read(vaultNotifierProvider.future);
        expect(state.status, equals(VaultStatus.unconfigured));
        expect(state.failedAttempts, equals(0));
        expect(state.isLockedOut, isFalse);
      },
    );

    test('setup creates master key and unlocks vault', () async {
      final notifier = container.read(vaultNotifierProvider.notifier);
      await notifier.setup('CorrectMasterPassword123!');

      final state = container.read(vaultNotifierProvider).value;
      expect(state, isNotNull);
      expect(state!.status, equals(VaultStatus.unlocked));
      expect(
        container.read(vaultKeyServiceProvider).isUnlockedInMemory,
        isTrue,
      );
    });

    test('lock transitions vault status to locked and drops the key', () async {
      final notifier = container.read(vaultNotifierProvider.notifier);
      await notifier.setup('CorrectMasterPassword123!');

      expect(
        container.read(vaultNotifierProvider).value!.status,
        equals(VaultStatus.unlocked),
      );

      notifier.lock();

      final lockedState = container.read(vaultNotifierProvider).value!;
      expect(lockedState.status, equals(VaultStatus.locked));
      expect(
        container.read(vaultKeyServiceProvider).isUnlockedInMemory,
        isFalse,
      );
    });

    test('unlock with correct password succeeds', () async {
      final notifier = container.read(vaultNotifierProvider.notifier);
      await notifier.setup('CorrectMasterPassword123!');
      notifier.lock();

      final success = await notifier.unlock('CorrectMasterPassword123!');
      expect(success, isTrue);

      final state = container.read(vaultNotifierProvider).value!;
      expect(state.status, equals(VaultStatus.unlocked));
      expect(
        container.read(vaultKeyServiceProvider).isUnlockedInMemory,
        isTrue,
      );
    });

    test(
      'unlock with wrong password increments failedAttempts counter',
      () async {
        final notifier = container.read(vaultNotifierProvider.notifier);
        await notifier.setup('CorrectMasterPassword123!');
        notifier.lock();

        final success = await notifier.unlock('WrongPassword!');
        expect(success, isFalse);

        final state = container.read(vaultNotifierProvider).value!;
        expect(state.status, equals(VaultStatus.locked));
        expect(state.failedAttempts, equals(1));
        expect(state.isLockedOut, isFalse);
      },
    );

    test(
      'brute-force protection engages lockout after 5 failed attempts',
      () async {
        final notifier = container.read(vaultNotifierProvider.notifier);
        await notifier.setup('CorrectMasterPassword123!');
        notifier.lock();

        // 4 failed attempts
        for (int i = 0; i < 4; i++) {
          await notifier.unlock('WrongPassword!');
        }

        final stateAfter4 = container.read(vaultNotifierProvider).value!;
        expect(stateAfter4.failedAttempts, equals(4));
        expect(stateAfter4.isLockedOut, isFalse);

        // 5th failed attempt -> engage lockout
        final success5 = await notifier.unlock('WrongPassword!');
        expect(success5, isFalse);

        final stateAfter5 = container.read(vaultNotifierProvider).value!;
        expect(stateAfter5.failedAttempts, equals(5));
        expect(stateAfter5.isLockedOut, isTrue);
        expect(stateAfter5.lockoutUntil, isNotNull);
        expect(stateAfter5.remainingLockout.inSeconds, greaterThan(0));

        // Attempting to unlock while locked out fails immediately
        final attemptDuringLockout = await notifier.unlock(
          'CorrectMasterPassword123!',
        );
        expect(attemptDuringLockout, isFalse);
      },
    );

    test(
      'failed attempts and lockout survive a new notifier instance',
      () async {
        final firstContainer = container;
        final notifier = firstContainer.read(vaultNotifierProvider.notifier);
        await notifier.setup('CorrectMasterPassword123!');
        notifier.lock();

        for (int i = 0; i < 5; i++) {
          await notifier.unlock('WrongPassword!');
        }
        firstContainer.dispose();

        final restartedContainer = ProviderContainer(
          overrides: [encryptionEngineProvider.overrideWithValue(fastEngine)],
        );
        addTearDown(restartedContainer.dispose);

        final restored = await restartedContainer.read(
          vaultNotifierProvider.future,
        );
        expect(restored.failedAttempts, equals(5));
        expect(restored.lockoutUntil, isNotNull);
        expect(restored.isLockedOut, isTrue);
      },
    );
  });
}
