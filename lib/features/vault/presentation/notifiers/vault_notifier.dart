import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../../../shared/storage/secure_storage_service.dart';

part 'vault_notifier.g.dart';

/// Represents the current status of the vault.
enum VaultStatus {
  /// No master password has been configured yet. Show setup screen.
  unconfigured,

  /// Master password exists but vault is currently locked. Show unlock screen.
  locked,

  /// Vault is unlocked and ready for use.
  unlocked,
}

/// Vault state holding the current status, active [SecretKey], and
/// brute-force protection counters.
class VaultState {
  final VaultStatus status;
  final SecretKey? masterKey;
  final int failedAttempts;
  final DateTime? lockoutUntil;

  const VaultState({
    required this.status,
    this.masterKey,
    this.failedAttempts = 0,
    this.lockoutUntil,
  });

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
    SecretKey? masterKey,
    int? failedAttempts,
    DateTime? lockoutUntil,
    bool clearMasterKey = false,
    bool clearLockout = false,
  }) {
    return VaultState(
      status: status ?? this.status,
      masterKey: clearMasterKey ? null : (masterKey ?? this.masterKey),
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockoutUntil: clearLockout ? null : (lockoutUntil ?? this.lockoutUntil),
    );
  }
}

/// Maximum number of failed unlock attempts before lockout engages.
const _kMaxAttemptsBeforeLockout = 5;

/// Manages the vault lifecycle: setup, lock, unlock, brute-force protection.
@Riverpod(keepAlive: true)
class VaultNotifier extends _$VaultNotifier {
  @override
  Future<VaultState> build() async {
    final storage = ref.watch(secureStorageServiceProvider);
    final hasMaster = await storage.containsKey(key: SecureStorageKeys.masterSalt);

    if (hasMaster) {
      return const VaultState(status: VaultStatus.locked);
    }
    return const VaultState(status: VaultStatus.unconfigured);
  }

  /// Creates a new vault with the given master password.
  ///
  /// Derives the master key in a background isolate to avoid UI jank.
  Future<void> setup(String masterPassword) async {
    final engine = ref.read(encryptionEngineProvider);
    final storage = ref.read(secureStorageServiceProvider);

    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final salt = engine.generateSalt();
      final secretKey = await engine.deriveMasterKeyInBackground(
        masterPassword: masterPassword,
        salt: salt,
      );

      final keyBytes = await secretKey.extractBytes();
      await storage.saveMasterSalt(salt);
      await storage.saveMasterKey(keyBytes);

      return VaultState(status: VaultStatus.unlocked, masterKey: secretKey);
    });
  }

  /// Unlocks the vault by deriving the key from the password and comparing it.
  ///
  /// Implements brute-force protection: after [_kMaxAttemptsBeforeLockout]
  /// failed attempts, imposes an exponentially increasing lockout period
  /// (30s → 60s → 120s → 240s, capped at 1 hour).
  Future<bool> unlock(String masterPassword) async {
    final currentState = state.valueOrNull;

    // Reject if currently in lockout period
    if (currentState != null && currentState.isLockedOut) {
      return false;
    }

    state = const AsyncLoading();

    final engine = ref.read(encryptionEngineProvider);
    final storage = ref.read(secureStorageServiceProvider);

    final salt = await storage.getMasterSalt();
    if (salt == null) {
      state = const AsyncData(VaultState(status: VaultStatus.unconfigured));
      return false;
    }

    final derivedKey = await engine.deriveMasterKeyInBackground(
      masterPassword: masterPassword,
      salt: salt,
    );

    final storedKeyBytes = await storage.getMasterKey();
    if (storedKeyBytes == null) {
      state = const AsyncData(VaultState(status: VaultStatus.locked));
      return false;
    }

    final derivedKeyBytes = await derivedKey.extractBytes();
    final isMatch = listEquals(derivedKeyBytes, storedKeyBytes);

    if (isMatch) {
      state = AsyncData(
        VaultState(status: VaultStatus.unlocked, masterKey: derivedKey),
      );
      return true;
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

    state = AsyncData(VaultState(
      status: VaultStatus.locked,
      failedAttempts: attempts,
      lockoutUntil: lockoutUntil,
    ));
    return false;
  }

  /// Locks the vault by clearing the master key from memory.
  void lock() {
    state = const AsyncData(VaultState(status: VaultStatus.locked));
  }
}
