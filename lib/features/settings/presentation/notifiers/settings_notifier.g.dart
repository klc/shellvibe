// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(settingsRepository)
final settingsRepositoryProvider = SettingsRepositoryProvider._();

final class SettingsRepositoryProvider
    extends
        $FunctionalProvider<
          SettingsRepository,
          SettingsRepository,
          SettingsRepository
        >
    with $Provider<SettingsRepository> {
  SettingsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsRepositoryHash();

  @$internal
  @override
  $ProviderElement<SettingsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SettingsRepository create(Ref ref) {
    return settingsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsRepository>(value),
    );
  }
}

String _$settingsRepositoryHash() =>
    r'718b69644c76e869689bd7ec94b4a8e9b6251501';

@ProviderFor(biometricLockService)
final biometricLockServiceProvider = BiometricLockServiceProvider._();

final class BiometricLockServiceProvider
    extends
        $FunctionalProvider<
          BiometricLockService,
          BiometricLockService,
          BiometricLockService
        >
    with $Provider<BiometricLockService> {
  BiometricLockServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'biometricLockServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$biometricLockServiceHash();

  @$internal
  @override
  $ProviderElement<BiometricLockService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  BiometricLockService create(Ref ref) {
    return biometricLockService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BiometricLockService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BiometricLockService>(value),
    );
  }
}

String _$biometricLockServiceHash() =>
    r'7da2795890f61cfe920aeaa39dbcbe6c90527c0b';

@ProviderFor(clipboardAutoClearService)
final clipboardAutoClearServiceProvider = ClipboardAutoClearServiceProvider._();

final class ClipboardAutoClearServiceProvider
    extends
        $FunctionalProvider<
          ClipboardAutoClearService,
          ClipboardAutoClearService,
          ClipboardAutoClearService
        >
    with $Provider<ClipboardAutoClearService> {
  ClipboardAutoClearServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clipboardAutoClearServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clipboardAutoClearServiceHash();

  @$internal
  @override
  $ProviderElement<ClipboardAutoClearService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ClipboardAutoClearService create(Ref ref) {
    return clipboardAutoClearService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClipboardAutoClearService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClipboardAutoClearService>(value),
    );
  }
}

String _$clipboardAutoClearServiceHash() =>
    r'5aa799948e4ea7cbd9c358a395de8ea57566ff2d';

@ProviderFor(SettingsNotifier)
final settingsProvider = SettingsNotifierProvider._();

final class SettingsNotifierProvider
    extends $AsyncNotifierProvider<SettingsNotifier, AppSettingsModel> {
  SettingsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsNotifierHash();

  @$internal
  @override
  SettingsNotifier create() => SettingsNotifier();
}

String _$settingsNotifierHash() => r'd025e1819bbbac01949951c611efed42f9a56a3c';

abstract class _$SettingsNotifier extends $AsyncNotifier<AppSettingsModel> {
  FutureOr<AppSettingsModel> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<AppSettingsModel>, AppSettingsModel>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AppSettingsModel>, AppSettingsModel>,
              AsyncValue<AppSettingsModel>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
