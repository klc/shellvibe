// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'identities_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Single app-wide owner of the vault Data Encryption Key.
///
/// Must be [Riverpod(keepAlive: true)]: the unwrapped DEK lives in this
/// instance's memory, so disposing it would silently re-lock the vault.

@ProviderFor(vaultKeyService)
final vaultKeyServiceProvider = VaultKeyServiceProvider._();

/// Single app-wide owner of the vault Data Encryption Key.
///
/// Must be [Riverpod(keepAlive: true)]: the unwrapped DEK lives in this
/// instance's memory, so disposing it would silently re-lock the vault.

final class VaultKeyServiceProvider
    extends
        $FunctionalProvider<VaultKeyService, VaultKeyService, VaultKeyService>
    with $Provider<VaultKeyService> {
  /// Single app-wide owner of the vault Data Encryption Key.
  ///
  /// Must be [Riverpod(keepAlive: true)]: the unwrapped DEK lives in this
  /// instance's memory, so disposing it would silently re-lock the vault.
  VaultKeyServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultKeyServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultKeyServiceHash();

  @$internal
  @override
  $ProviderElement<VaultKeyService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VaultKeyService create(Ref ref) {
    return vaultKeyService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultKeyService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultKeyService>(value),
    );
  }
}

String _$vaultKeyServiceHash() => r'caadb88781a273b41c629f9b10b13975fbacfc9f';

/// E2EE backup service. Needs the vault key to make backups self-contained.

@ProviderFor(e2eeCloudSyncService)
final e2eeCloudSyncServiceProvider = E2eeCloudSyncServiceProvider._();

/// E2EE backup service. Needs the vault key to make backups self-contained.

final class E2eeCloudSyncServiceProvider
    extends
        $FunctionalProvider<
          E2EECloudSyncService,
          E2EECloudSyncService,
          E2EECloudSyncService
        >
    with $Provider<E2EECloudSyncService> {
  /// E2EE backup service. Needs the vault key to make backups self-contained.
  E2eeCloudSyncServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'e2eeCloudSyncServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$e2eeCloudSyncServiceHash();

  @$internal
  @override
  $ProviderElement<E2EECloudSyncService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  E2EECloudSyncService create(Ref ref) {
    return e2eeCloudSyncService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(E2EECloudSyncService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<E2EECloudSyncService>(value),
    );
  }
}

String _$e2eeCloudSyncServiceHash() =>
    r'bf2f1b5423f6687f6895a033da733ebf1df434c8';

@ProviderFor(vaultRepository)
final vaultRepositoryProvider = VaultRepositoryProvider._();

final class VaultRepositoryProvider
    extends
        $FunctionalProvider<VaultRepository, VaultRepository, VaultRepository>
    with $Provider<VaultRepository> {
  VaultRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultRepositoryHash();

  @$internal
  @override
  $ProviderElement<VaultRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VaultRepository create(Ref ref) {
    return vaultRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultRepository>(value),
    );
  }
}

String _$vaultRepositoryHash() => r'cb4a8000132776b509d5cc80e3258f00d47d1523';

@ProviderFor(IdentitiesNotifier)
final identitiesProvider = IdentitiesNotifierProvider._();

final class IdentitiesNotifierProvider
    extends $AsyncNotifierProvider<IdentitiesNotifier, List<IdentityModel>> {
  IdentitiesNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'identitiesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$identitiesNotifierHash();

  @$internal
  @override
  IdentitiesNotifier create() => IdentitiesNotifier();
}

String _$identitiesNotifierHash() =>
    r'0f735644988d91b6df04a249198e6723739967ca';

abstract class _$IdentitiesNotifier
    extends $AsyncNotifier<List<IdentityModel>> {
  FutureOr<List<IdentityModel>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<IdentityModel>>, List<IdentityModel>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<IdentityModel>>, List<IdentityModel>>,
              AsyncValue<List<IdentityModel>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Identities that need repairing, recomputed whenever the identity list or the
/// vault's lock state changes.
///
/// Kept out of [IdentitiesNotifier.build] on purpose: listing identities must
/// stay possible while the vault is locked, and must not decrypt secrets as a
/// side effect of drawing a list.

@ProviderFor(undecryptableIdentityIds)
final undecryptableIdentityIdsProvider = UndecryptableIdentityIdsProvider._();

/// Identities that need repairing, recomputed whenever the identity list or the
/// vault's lock state changes.
///
/// Kept out of [IdentitiesNotifier.build] on purpose: listing identities must
/// stay possible while the vault is locked, and must not decrypt secrets as a
/// side effect of drawing a list.

final class UndecryptableIdentityIdsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Set<String>>,
          Set<String>,
          FutureOr<Set<String>>
        >
    with $FutureModifier<Set<String>>, $FutureProvider<Set<String>> {
  /// Identities that need repairing, recomputed whenever the identity list or the
  /// vault's lock state changes.
  ///
  /// Kept out of [IdentitiesNotifier.build] on purpose: listing identities must
  /// stay possible while the vault is locked, and must not decrypt secrets as a
  /// side effect of drawing a list.
  UndecryptableIdentityIdsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'undecryptableIdentityIdsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$undecryptableIdentityIdsHash();

  @$internal
  @override
  $FutureProviderElement<Set<String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Set<String>> create(Ref ref) {
    return undecryptableIdentityIds(ref);
  }
}

String _$undecryptableIdentityIdsHash() =>
    r'a7f91f1a3ee37f9937e0085deeaf5d5d694e74ca';
