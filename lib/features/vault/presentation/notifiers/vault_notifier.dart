import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'identities_notifier.dart';

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

/// Vault state holding the current status and brute-force protection counters.
///
/// The Data Encryption Key itself is deliberately **not** held here — it lives
/// in [VaultKeyService] alone, so there is exactly one in-memory copy.
class VaultState {
  final VaultStatus status;
  final int failedAttempts;
  final DateTime? lockoutUntil;

  const VaultState({
    required this.status,
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
    int? failedAttempts,
    DateTime? lockoutUntil,
    bool clearLockout = false,
  }) {
    return VaultState(
      status: status ?? this.status,
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
    final keyService = ref.watch(vaultKeyServiceProvider);
    if (!await keyService.isMasterPasswordConfigured()) {
      return const VaultState(status: VaultStatus.unconfigured);
    }
    return VaultState(
      status: keyService.isUnlockedInMemory
          ? VaultStatus.unlocked
          : VaultStatus.locked,
    );
  }

  /// Protects the vault with a master password.
  ///
  /// Wraps the existing Data Encryption Key rather than replacing it, so
  /// identities saved before setup stay decryptable. The Argon2id derivation
  /// runs in a background isolate to avoid UI jank.
  Future<void> setup(String masterPassword) async {
    final keyService = ref.read(vaultKeyServiceProvider);

    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      await keyService.configureMasterPassword(masterPassword);
      return const VaultState(status: VaultStatus.unlocked);
    });
  }

  /// Unlocks the vault by unwrapping the DEK with the master password.
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

    final keyService = ref.read(vaultKeyServiceProvider);

    try {
      if (!await keyService.isMasterPasswordConfigured()) {
        state = const AsyncData(VaultState(status: VaultStatus.unconfigured));
        return false;
      }

      if (await keyService.unlock(masterPassword)) {
        state = const AsyncData(VaultState(status: VaultStatus.unlocked));
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
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  /// Locks the vault by dropping the unwrapped DEK from memory.
  void lock() {
    ref.read(vaultKeyServiceProvider).lock();
    state = const AsyncData(VaultState(status: VaultStatus.locked));
  }
}
