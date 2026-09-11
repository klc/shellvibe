// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Manages the vault lifecycle: setup, lock, unlock, brute-force protection.

@ProviderFor(VaultNotifier)
final vaultProvider = VaultNotifierProvider._();

/// Manages the vault lifecycle: setup, lock, unlock, brute-force protection.
final class VaultNotifierProvider
    extends $AsyncNotifierProvider<VaultNotifier, VaultState> {
  /// Manages the vault lifecycle: setup, lock, unlock, brute-force protection.
  VaultNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultNotifierHash();

  @$internal
  @override
  VaultNotifier create() => VaultNotifier();
}

String _$vaultNotifierHash() => r'999c380017b2abbd51f205bb4eb76596f67deeed';

/// Manages the vault lifecycle: setup, lock, unlock, brute-force protection.

abstract class _$VaultNotifier extends $AsyncNotifier<VaultState> {
  FutureOr<VaultState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<VaultState>, VaultState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<VaultState>, VaultState>,
              AsyncValue<VaultState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
