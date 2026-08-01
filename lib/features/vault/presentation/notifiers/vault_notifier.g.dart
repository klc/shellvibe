// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$vaultNotifierHash() => r'51aefaa902884cbb198ab4693aebacc2f0c4aefb';

/// Manages the vault lifecycle: setup, lock, unlock, brute-force protection.
///
/// Copied from [VaultNotifier].
@ProviderFor(VaultNotifier)
final vaultNotifierProvider =
    AsyncNotifierProvider<VaultNotifier, VaultState>.internal(
      VaultNotifier.new,
      name: r'vaultNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$vaultNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$VaultNotifier = AsyncNotifier<VaultState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
