// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'identities_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$vaultRepositoryHash() => r'2a0f79b2d4503095c7703a45e492e29bd470c8b5';

/// See also [vaultRepository].
@ProviderFor(vaultRepository)
final vaultRepositoryProvider = AutoDisposeProvider<VaultRepository>.internal(
  vaultRepository,
  name: r'vaultRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$vaultRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef VaultRepositoryRef = AutoDisposeProviderRef<VaultRepository>;
String _$identitiesNotifierHash() =>
    r'539078c2f6cf430fa93f598ab61fa8d2d268d84a';

/// See also [IdentitiesNotifier].
@ProviderFor(IdentitiesNotifier)
final identitiesNotifierProvider =
    AutoDisposeAsyncNotifierProvider<
      IdentitiesNotifier,
      List<IdentityModel>
    >.internal(
      IdentitiesNotifier.new,
      name: r'identitiesNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$identitiesNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$IdentitiesNotifier = AutoDisposeAsyncNotifier<List<IdentityModel>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
