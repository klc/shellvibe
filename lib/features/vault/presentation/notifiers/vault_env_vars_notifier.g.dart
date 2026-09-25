// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_env_vars_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(vaultEnvRepository)
final vaultEnvRepositoryProvider = VaultEnvRepositoryProvider._();

final class VaultEnvRepositoryProvider
    extends
        $FunctionalProvider<
          VaultEnvRepository,
          VaultEnvRepository,
          VaultEnvRepository
        >
    with $Provider<VaultEnvRepository> {
  VaultEnvRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultEnvRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultEnvRepositoryHash();

  @$internal
  @override
  $ProviderElement<VaultEnvRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  VaultEnvRepository create(Ref ref) {
    return vaultEnvRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VaultEnvRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VaultEnvRepository>(value),
    );
  }
}

String _$vaultEnvRepositoryHash() =>
    r'6552fadbc7cae87ef5700a98866d32dd9e680c08';

@ProviderFor(VaultEnvVarsNotifier)
final vaultEnvVarsProvider = VaultEnvVarsNotifierProvider._();

final class VaultEnvVarsNotifierProvider
    extends
        $AsyncNotifierProvider<VaultEnvVarsNotifier, List<VaultEnvVarModel>> {
  VaultEnvVarsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vaultEnvVarsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vaultEnvVarsNotifierHash();

  @$internal
  @override
  VaultEnvVarsNotifier create() => VaultEnvVarsNotifier();
}

String _$vaultEnvVarsNotifierHash() =>
    r'03502a1adc870764b21268af285e59e69bce17d1';

abstract class _$VaultEnvVarsNotifier
    extends $AsyncNotifier<List<VaultEnvVarModel>> {
  FutureOr<List<VaultEnvVarModel>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<List<VaultEnvVarModel>>, List<VaultEnvVarModel>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<VaultEnvVarModel>>,
                List<VaultEnvVarModel>
              >,
              AsyncValue<List<VaultEnvVarModel>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
