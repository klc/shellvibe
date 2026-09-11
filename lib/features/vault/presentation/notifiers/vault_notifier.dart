import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../../../shared/storage/secure_storage_service.dart';
import 'identities_notifier.dart';

part 'vault_notifier.g.dart';

/// How long a lock waits for already-admitted protected writes to commit.
///
/// Long enough for a local SQLite transaction, short enough that a wedged
/// write cannot keep the decryption key in memory behind a UI that already
/// reads as locked.
const Duration vaultLockDrainTimeout = Duration(seconds: 5);

/// Shortens [vaultLockDrainTimeout] in tests that exercise the wedged-write
/// path, so they do not spend the full grace period in real time.
@visibleForTesting
Duration? debugVaultLockDrainTimeoutOverride;

/// Represents the current status of the vault.
enum VaultStatus {
  /// No master password has been configured yet. Show setup screen.
  unconfigured,

  /// Master password exists but vault is currently locked. Show unlock screen.
  locked,

  /// Vault is unlocked and ready for use.
  unlocked,
}

/// Vault state holding the current status and brute-force protection counters.
///
/// The Data Encryption Key itself is deliberately **not** held here — it lives
/// in [VaultKeyService] alone, so there is exactly one in-memory copy.
class VaultState {
  final VaultStatus status;
  final int failedAttempts;
  final DateTime? lockoutUntil;

  /// A lock has been requested but existing durable writes are still draining.
  ///
  /// The DEK may remain in memory for that short period so the write that was
  /// already admitted can commit, but no new capability may treat the vault as
  /// available.
  final bool isLocking;

  const VaultState({
    required this.status,
    this.failedAttempts = 0,
    this.lockoutUntil,
    this.isLocking = false,
  });

  /// Whether a Device Link capability may be admitted for this vault state.
  bool get allowsDeviceLink => status != VaultStatus.locked && !isLocking;

  /// Returns true if the vault is currently in a brute-force lockout period.
  bool get isLockedOut =>
      lockoutUntil != null && DateTime.now().isBefore(lockoutUntil!);

  /// Remaining duration of the current lockout period.
  Duration get remainingLockout {
    if (lockoutUntil == null) return Duration.zero;
    final remaining = lockoutUntil!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  VaultState copyWith({
    VaultStatus? status,
    int? failedAttempts,
    DateTime? lockoutUntil,
    bool clearLockout = false,
    bool? isLocking,
  }) {
    return VaultState(
      status: status ?? this.status,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockoutUntil: clearLockout ? null : (lockoutUntil ?? this.lockoutUntil),
      isLocking: isLocking ?? this.isLocking,
    );
  }
}

/// Maximum number of failed unlock attempts before lockout engages.
const _kMaxAttemptsBeforeLockout = 5;

/// Manages the vault lifecycle: setup, lock, unlock, brute-force protection.
@Riverpod(keepAlive: true)
class VaultNotifier extends _$VaultNotifier {
  /// Serializes unlock attempts so concurrent Argon2id operations cannot
  /// observe and persist the same failed-attempt counter.
  Future<void> _unlockQueue = Future<void>.value();

  /// Bumped by [lock]. Async continuations (unlock/setup) capture it up front
  /// and refuse to publish an `unlocked` state if the vault was locked while
  /// they were awaiting — otherwise a background auto-lock during an in-flight
  /// unlock would leave the UI reporting an unlocked vault with no DEK in
  /// [VaultKeyService].
  int _lifecycleGeneration = 0;

  /// Whether [lock] has started closing the vault to new protected writes.
  bool _isLocking = false;

  /// Number of writes that received an unlocked-vault permit and have not yet
  /// completed their durable work.
  int _activeUnlockedWrites = 0;
  Completer<void>? _unlockedWritesDrained;
  Future<void>? _lockTransition;

  @override
  Future<VaultState> build() async {
    final keyService = ref.watch(vaultKeyServiceProvider);
    final storage = ref.watch(secureStorageServiceProvider);
    if (!await keyService.isMasterPasswordConfigured()) {
      return const VaultState(status: VaultStatus.unconfigured);
    }
    final failedAttempts =
        int.tryParse(
          await storage.read(key: SecureStorageKeys.vaultFailedAttempts) ?? '',
        ) ??
        0;
    final lockoutMillis = int.tryParse(
      await storage.read(key: SecureStorageKeys.vaultLockoutUntil) ?? '',
    );
    return VaultState(
      status: keyService.isUnlockedInMemory
          ? VaultStatus.unlocked
          : VaultStatus.locked,
      failedAttempts: failedAttempts,
      lockoutUntil: lockoutMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lockoutMillis),
    );
  }

  /// Protects the vault with a master password.
  ///
  /// Wraps the existing Data Encryption Key rather than replacing it, so
  /// identities saved before setup stay decryptable. The Argon2id derivation
  /// runs in a background isolate to avoid UI jank.
  Future<void> setup(String masterPassword) async {
    if (_isLocking) {
      throw StateError('Vault is locking');
    }
    final generation = _lifecycleGeneration;
    final keyService = ref.read(vaultKeyServiceProvider);

    state = const AsyncLoading();
    try {
      await keyService.configureMasterPassword(masterPassword);
      if (!_isCurrentLifecycle(generation)) {
        keyService.lock();
        return;
      }
      await _clearBruteForceState();
      if (!_isCurrentLifecycle(generation)) {
        keyService.lock();
        return;
      }
      state = const AsyncData(VaultState(status: VaultStatus.unlocked));
    } catch (error, stackTrace) {
      if (!_isCurrentLifecycle(generation)) {
        keyService.lock();
        return;
      }
      state = AsyncError(error, stackTrace);
    }
  }

  /// Removes master-password protection after verifying [currentPassword].
  ///
  /// Verification runs through [unlock], so a wrong password here is subject to
  /// the same brute-force lockout as the unlock screen and cannot be used as an
  /// oracle that bypasses it. On success the Data Encryption Key returns to the
  /// OS keychain in plaintext form, which is what makes the vault openable
  /// again without a prompt — the vault is no longer protected by a password.
  ///
  /// Returns false when the password is wrong or a lockout is in effect.
  Future<bool> removeMasterPassword(String currentPassword) async {
    final keyService = ref.read(vaultKeyServiceProvider);
    if (!await keyService.isMasterPasswordConfigured()) return true;

    if (!await unlock(currentPassword)) return false;

    try {
      await keyService.removeMasterPassword();
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }

    // A lock may have been requested while the removal ran. Its pending
    // transition would otherwise publish `locked` after this method returns,
    // stranding the user on an unlock screen for a vault that no longer has a
    // password. Let it finish first, then state the real outcome.
    final pendingLock = _lockTransition;
    if (pendingLock != null) await pendingLock;

    state = const AsyncData(VaultState(status: VaultStatus.unconfigured));
    return true;
  }

  /// Unlocks the vault by unwrapping the DEK with the master password.
  ///
  /// Implements brute-force protection: after [_kMaxAttemptsBeforeLockout]
  /// failed attempts, imposes an exponentially increasing lockout period
  /// (30s → 60s → 120s → 240s, capped at 1 hour).
  Future<bool> unlock(String masterPassword) async {
    final operation = _unlockQueue.then((_) => _unlockInternal(masterPassword));
    _unlockQueue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }

  Future<bool> _unlockInternal(String masterPassword) async {
    if (_isLocking) return false;
    final generation = _lifecycleGeneration;
    final currentState = state.value;

    // Reject if currently in lockout period
    if (currentState != null && currentState.isLockedOut) {
      return false;
    }

    state = const AsyncLoading();

    final keyService = ref.read(vaultKeyServiceProvider);

    try {
      if (!await keyService.isMasterPasswordConfigured()) {
        if (!_isCurrentLifecycle(generation)) {
          keyService.lock();
          return false;
        }
        state = const AsyncData(VaultState(status: VaultStatus.unconfigured));
        return false;
      }

      if (await keyService.unlock(masterPassword)) {
        // Locked while the Argon2id derivation was running? The DEK is gone;
        // publishing `unlocked` here would desync UI from [VaultKeyService].
        if (!_isCurrentLifecycle(generation)) {
          keyService.lock();
          return false;
        }
        await _clearBruteForceState();
        if (!_isCurrentLifecycle(generation)) {
          keyService.lock();
          return false;
        }
        state = const AsyncData(VaultState(status: VaultStatus.unlocked));
        return true;
      }

      if (!_isCurrentLifecycle(generation)) {
        keyService.lock();
        return false;
      }

      // --- Brute-force protection ---
      final attempts = (currentState?.failedAttempts ?? 0) + 1;
      DateTime? lockoutUntil;

      if (attempts >= _kMaxAttemptsBeforeLockout) {
        // Exponential backoff: 30s, 60s, 120s, 240s… capped at 3600s (1h)
        final exponent = attempts - _kMaxAttemptsBeforeLockout;
        final lockoutSeconds = (30 * (1 << exponent)).clamp(30, 3600);
        lockoutUntil = DateTime.now().add(Duration(seconds: lockoutSeconds));
      }

      state = AsyncData(
        VaultState(
          status: VaultStatus.locked,
          failedAttempts: attempts,
          lockoutUntil: lockoutUntil,
        ),
      );
      await _persistBruteForceState(attempts, lockoutUntil);
      if (!_isCurrentLifecycle(generation)) {
        keyService.lock();
        return false;
      }
      return false;
    } catch (e, st) {
      if (!_isCurrentLifecycle(generation)) {
        keyService.lock();
        return false;
      }
      state = AsyncError(e, st);
      return false;
    }
  }

  /// Whether a protected write may start right now.
  ///
  /// Deliberately the same predicate [VaultState.allowsDeviceLink] uses, so a
  /// capability gate and the write gate behind it can never disagree. Note
  /// that `unconfigured` passes both: before a master password exists there is
  /// no DEK to protect, and refusing here would make Device Link unreachable
  /// on a fresh install rather than more secure.
  bool get _allowsProtectedWrite {
    final current = state;
    return !_isLocking &&
        !current.isLoading &&
        !current.hasError &&
        current.hasValue &&
        current.value!.allowsDeviceLink;
  }

  /// Runs [operation] while the vault is available for a durable write.
  ///
  /// [lock] first closes this gate to new callers, then waits for every
  /// outstanding permit to finish. A database operation must therefore await
  /// its SQLite transaction before returning from [operation], which keeps its
  /// commit on the unlocked side of the lifecycle boundary.
  Future<T> runWhileUnlocked<T>(Future<T> Function() operation) async {
    if (!_allowsProtectedWrite) {
      throw StateError('Vault is not available for a protected write');
    }

    _activeUnlockedWrites++;
    _unlockedWritesDrained ??= Completer<void>();
    try {
      return await operation();
    } finally {
      _activeUnlockedWrites--;
      if (_activeUnlockedWrites == 0) {
        _unlockedWritesDrained?.complete();
        _unlockedWritesDrained = null;
      }
    }
  }

  /// Locks the vault by dropping the unwrapped DEK from memory.
  ///
  /// Once requested, the lock rejects new unlocked-write permits immediately
  /// but delays the visible locked transition until any existing permit has
  /// completed its durable write.
  Future<void> lock() {
    if (_isLocking) return _lockTransition ?? Future<void>.value();
    _lifecycleGeneration++;
    _isLocking = true;
    final current = state.value;
    final lockingState = VaultState(
      // A vault that has never been configured must remain set-up eligible;
      // every configured vault becomes visibly locked at request time while
      // `isLocking` closes all sensitive capability gates immediately.
      status: current?.status == VaultStatus.unconfigured
          ? VaultStatus.unconfigured
          : VaultStatus.locked,
      failedAttempts: current?.failedAttempts ?? 0,
      lockoutUntil: current?.lockoutUntil,
      isLocking: true,
    );
    state = AsyncData(lockingState);

    late final Future<void> transition;
    transition = _finishLockAfterUnlockedWrites(lockingState).whenComplete(() {
      if (identical(_lockTransition, transition)) {
        _lockTransition = null;
        _isLocking = false;
      }
    });
    _lockTransition = transition;
    return transition;
  }

  Future<void> _finishLockAfterUnlockedWrites(VaultState lockingState) async {
    final writesDrained = _unlockedWritesDrained;
    if (writesDrained != null) {
      try {
        await writesDrained.future.timeout(
          debugVaultLockDrainTimeoutOverride ?? vaultLockDrainTimeout,
        );
      } on TimeoutException {
        // A write that never returns must not keep the DEK resident: the grace
        // period exists for a commit that is about to land, not as an
        // open-ended hold. Drop the key and let the stuck write fail.
        _unlockedWritesDrained = null;
      }
    }
    ref.read(vaultKeyServiceProvider).lock();
    state = AsyncData(
      VaultState(
        status: lockingState.status == VaultStatus.unconfigured
            ? VaultStatus.unconfigured
            : VaultStatus.locked,
        failedAttempts: lockingState.failedAttempts,
        lockoutUntil: lockingState.lockoutUntil,
      ),
    );
  }

  bool _isCurrentLifecycle(int generation) =>
      generation == _lifecycleGeneration && !_isLocking;

  Future<void> _persistBruteForceState(
    int failedAttempts,
    DateTime? lockoutUntil,
  ) async {
    final storage = ref.read(secureStorageServiceProvider);
    await storage.write(
      key: SecureStorageKeys.vaultFailedAttempts,
      value: '$failedAttempts',
    );
    if (lockoutUntil == null) {
      await storage.delete(key: SecureStorageKeys.vaultLockoutUntil);
    } else {
      await storage.write(
        key: SecureStorageKeys.vaultLockoutUntil,
        value: '${lockoutUntil.millisecondsSinceEpoch}',
      );
    }
  }

  Future<void> _clearBruteForceState() async {
    final storage = ref.read(secureStorageServiceProvider);
    await storage.delete(key: SecureStorageKeys.vaultFailedAttempts);
    await storage.delete(key: SecureStorageKeys.vaultLockoutUntil);
  }
}
