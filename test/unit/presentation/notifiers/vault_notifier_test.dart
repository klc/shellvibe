import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/identities_notifier.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/vault_notifier.dart';

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
        final state = await container.read(vaultProvider.future);
        expect(state.status, equals(VaultStatus.unconfigured));
        expect(state.failedAttempts, equals(0));
        expect(state.isLockedOut, isFalse);
      },
    );

    test('setup creates master key and unlocks vault', () async {
      final notifier = container.read(vaultProvider.notifier);
      await notifier.setup('CorrectMasterPassword123!');

      final state = container.read(vaultProvider).value;
      expect(state, isNotNull);
      expect(state!.status, equals(VaultStatus.unlocked));
      expect(
        container.read(vaultKeyServiceProvider).isUnlockedInMemory,
        isTrue,
      );
    });

    test('lock transitions vault status to locked and drops the key', () async {
      final notifier = container.read(vaultProvider.notifier);
      await notifier.setup('CorrectMasterPassword123!');

      expect(
        container.read(vaultProvider).value!.status,
        equals(VaultStatus.unlocked),
      );

      notifier.lock();

      final lockedState = container.read(vaultProvider).value!;
      expect(lockedState.status, equals(VaultStatus.locked));
      expect(
        container.read(vaultKeyServiceProvider).isUnlockedInMemory,
        isFalse,
      );
    });

    test(
      'lock serializes active unlocked writes and rejects new permits',
      () async {
        final notifier = container.read(vaultProvider.notifier);
        await notifier.setup('CorrectMasterPassword123!');
        final enteredWrite = Completer<void>();
        final releaseWrite = Completer<void>();

        final write = notifier.runWhileUnlocked(() async {
          enteredWrite.complete();
          await releaseWrite.future;
        });
        await enteredWrite.future;

        final lock = notifier.lock();
        final lockingState = container.read(vaultProvider).value!;
        expect(lockingState.status, VaultStatus.locked);
        expect(lockingState.isLocking, isTrue);
        expect(lockingState.allowsDeviceLink, isFalse);
        expect(
          notifier.runWhileUnlocked(() async {}),
          throwsA(isA<StateError>()),
        );

        releaseWrite.complete();
        await write;
        await lock;

        expect(container.read(vaultProvider).value!.status, VaultStatus.locked);
        expect(container.read(vaultProvider).value!.isLocking, isFalse);
        expect(
          container.read(vaultKeyServiceProvider).isUnlockedInMemory,
          isFalse,
        );
      },
    );

    test(
      'lock drops the key even when a permitted write never returns',
      () async {
        debugVaultLockDrainTimeoutOverride = const Duration(milliseconds: 50);
        addTearDown(() => debugVaultLockDrainTimeoutOverride = null);

        final notifier = container.read(vaultProvider.notifier);
        await notifier.setup('CorrectMasterPassword123!');
        expect(
          container.read(vaultKeyServiceProvider).isUnlockedInMemory,
          isTrue,
        );

        // A write that is admitted and then wedges must not hold the DEK in
        // memory behind a UI that already reads as locked.
        final wedged = Completer<void>();
        final write = notifier.runWhileUnlocked(() => wedged.future);
        unawaited(write.catchError((_) {}));

        await notifier.lock();

        expect(
          container.read(vaultKeyServiceProvider).isUnlockedInMemory,
          isFalse,
        );
        expect(container.read(vaultProvider).value!.status, VaultStatus.locked);
        expect(container.read(vaultProvider).value!.isLocking, isFalse);
        // The gate stays shut for anything that arrives afterwards.
        expect(
          notifier.runWhileUnlocked(() async {}),
          throwsA(isA<StateError>()),
        );

        wedged.complete();
        await write;
      },
    );

    test('unlock with correct password succeeds', () async {
      final notifier = container.read(vaultProvider.notifier);
      await notifier.setup('CorrectMasterPassword123!');
      notifier.lock();

      final success = await notifier.unlock('CorrectMasterPassword123!');
      expect(success, isTrue);

      final state = container.read(vaultProvider).value!;
      expect(state.status, equals(VaultStatus.unlocked));
      expect(
        container.read(vaultKeyServiceProvider).isUnlockedInMemory,
        isTrue,
      );
    });

    test(
      'unlock with wrong password increments failedAttempts counter',
      () async {
        final notifier = container.read(vaultProvider.notifier);
        await notifier.setup('CorrectMasterPassword123!');
        notifier.lock();

        final success = await notifier.unlock('WrongPassword!');
        expect(success, isFalse);

        final state = container.read(vaultProvider).value!;
        expect(state.status, equals(VaultStatus.locked));
        expect(state.failedAttempts, equals(1));
        expect(state.isLockedOut, isFalse);
      },
    );

    test(
      'brute-force protection engages lockout after 5 failed attempts',
      () async {
        final notifier = container.read(vaultProvider.notifier);
        await notifier.setup('CorrectMasterPassword123!');
        notifier.lock();

        // 4 failed attempts
        for (int i = 0; i < 4; i++) {
          await notifier.unlock('WrongPassword!');
        }

        final stateAfter4 = container.read(vaultProvider).value!;
        expect(stateAfter4.failedAttempts, equals(4));
        expect(stateAfter4.isLockedOut, isFalse);

        // 5th failed attempt -> engage lockout
        final success5 = await notifier.unlock('WrongPassword!');
        expect(success5, isFalse);

        final stateAfter5 = container.read(vaultProvider).value!;
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
      'serializes concurrent failed unlocks and persists every attempt',
      () async {
        final notifier = container.read(vaultProvider.notifier);
        await notifier.setup('CorrectMasterPassword123!');
        notifier.lock();

        final results = await Future.wait(
          List.generate(5, (_) => notifier.unlock('WrongPassword!')),
        );

        expect(results.every((result) => result == false), isTrue);
        final state = container.read(vaultProvider).value!;
        expect(state.failedAttempts, equals(5));
        expect(state.isLockedOut, isTrue);

        final storage = container.read(secureStorageServiceProvider);
        expect(
          await storage.read(key: SecureStorageKeys.vaultFailedAttempts),
          equals('5'),
        );
      },
    );

    test(
      'failed attempts and lockout survive a new notifier instance',
      () async {
        final firstContainer = container;
        final notifier = firstContainer.read(vaultProvider.notifier);
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

        final restored = await restartedContainer.read(vaultProvider.future);
        expect(restored.failedAttempts, equals(5));
        expect(restored.lockoutUntil, isNotNull);
        expect(restored.isLockedOut, isTrue);
      },
    );

    test('removeMasterPassword returns the vault to unconfigured', () async {
      final notifier = container.read(vaultProvider.notifier);
      await notifier.setup('CorrectMasterPassword123!');

      final removed = await notifier.removeMasterPassword(
        'CorrectMasterPassword123!',
      );

      expect(removed, isTrue);
      expect(
        container.read(vaultProvider).value!.status,
        equals(VaultStatus.unconfigured),
      );
      final keyService = container.read(vaultKeyServiceProvider);
      expect(await keyService.isMasterPasswordConfigured(), isFalse);
      expect(await keyService.getDek(), isNotNull);
    });

    test(
      'removeMasterPassword keeps the same DEK, so secrets survive',
      () async {
        final notifier = container.read(vaultProvider.notifier);
        final keyService = container.read(vaultKeyServiceProvider);

        final before = await (await keyService.getDek()).extractBytes();
        await notifier.setup('CorrectMasterPassword123!');
        await notifier.removeMasterPassword('CorrectMasterPassword123!');
        final after = await (await keyService.getDek()).extractBytes();

        expect(after, equals(before));
      },
    );

    test('removeMasterPassword rejects a wrong password', () async {
      final notifier = container.read(vaultProvider.notifier);
      await notifier.setup('CorrectMasterPassword123!');

      final removed = await notifier.removeMasterPassword('WrongPassword!');

      expect(removed, isFalse);
      expect(
        await container
            .read(vaultKeyServiceProvider)
            .isMasterPasswordConfigured(),
        isTrue,
      );
      expect(container.read(vaultProvider).value!.failedAttempts, equals(1));
    });

    test('removeMasterPassword works from a locked vault', () async {
      final notifier = container.read(vaultProvider.notifier);
      await notifier.setup('CorrectMasterPassword123!');
      await notifier.lock();

      final removed = await notifier.removeMasterPassword(
        'CorrectMasterPassword123!',
      );

      expect(removed, isTrue);
      expect(
        container.read(vaultProvider).value!.status,
        equals(VaultStatus.unconfigured),
      );
    });

    test(
      'removeMasterPassword is refused while a lockout is in effect',
      () async {
        final notifier = container.read(vaultProvider.notifier);
        await notifier.setup('CorrectMasterPassword123!');
        await notifier.lock();
        for (int i = 0; i < 5; i++) {
          await notifier.unlock('WrongPassword!');
        }
        expect(container.read(vaultProvider).value!.isLockedOut, isTrue);

        final removed = await notifier.removeMasterPassword(
          'CorrectMasterPassword123!',
        );

        expect(removed, isFalse);
        expect(
          await container
              .read(vaultKeyServiceProvider)
              .isMasterPasswordConfigured(),
          isTrue,
        );
      },
    );

    test('removeMasterPassword on an unprotected vault is a no-op', () async {
      final notifier = container.read(vaultProvider.notifier);
      await container.read(vaultProvider.future);

      expect(await notifier.removeMasterPassword('anything'), isTrue);
      expect(
        container.read(vaultProvider).value!.status,
        equals(VaultStatus.unconfigured),
      );
    });
  });
}
