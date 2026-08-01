// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'identities_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$vaultKeyServiceHash() => r'0251518b091852e50a3f769d8741ac22a27983d2';

/// Single app-wide owner of the vault Data Encryption Key.
///
/// Must be [Riverpod(keepAlive: true)]: the unwrapped DEK lives in this
/// instance's memory, so disposing it would silently re-lock the vault.
///
/// Copied from [vaultKeyService].
@ProviderFor(vaultKeyService)
final vaultKeyServiceProvider = Provider<VaultKeyService>.internal(
  vaultKeyService,
  name: r'vaultKeyServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$vaultKeyServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef VaultKeyServiceRef = ProviderRef<VaultKeyService>;
String _$e2eeCloudSyncServiceHash() =>
    r'0955726e4637d33dca33e9f46be8173438123481';

/// E2EE backup service. Needs the vault key to make backups self-contained.
///
/// Copied from [e2eeCloudSyncService].
@ProviderFor(e2eeCloudSyncService)
final e2eeCloudSyncServiceProvider =
    AutoDisposeProvider<E2EECloudSyncService>.internal(
      e2eeCloudSyncService,
      name: r'e2eeCloudSyncServiceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$e2eeCloudSyncServiceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef E2eeCloudSyncServiceRef = AutoDisposeProviderRef<E2EECloudSyncService>;
String _$vaultRepositoryHash() => r'957541caf7aa9309d22dcae761bd8eca46a433a2';

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
    r'57d2c4c972096217db45269466986848de7777e0';

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
