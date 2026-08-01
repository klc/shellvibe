// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$settingsRepositoryHash() =>
    r'718b69644c76e869689bd7ec94b4a8e9b6251501';

/// See also [settingsRepository].
@ProviderFor(settingsRepository)
final settingsRepositoryProvider =
    AutoDisposeProvider<SettingsRepository>.internal(
      settingsRepository,
      name: r'settingsRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$settingsRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SettingsRepositoryRef = AutoDisposeProviderRef<SettingsRepository>;
String _$biometricLockServiceHash() =>
    r'7da2795890f61cfe920aeaa39dbcbe6c90527c0b';

/// See also [biometricLockService].
@ProviderFor(biometricLockService)
final biometricLockServiceProvider =
    AutoDisposeProvider<BiometricLockService>.internal(
      biometricLockService,
      name: r'biometricLockServiceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$biometricLockServiceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BiometricLockServiceRef = AutoDisposeProviderRef<BiometricLockService>;
String _$clipboardAutoClearServiceHash() =>
    r'5aa799948e4ea7cbd9c358a395de8ea57566ff2d';

/// See also [clipboardAutoClearService].
@ProviderFor(clipboardAutoClearService)
final clipboardAutoClearServiceProvider =
    Provider<ClipboardAutoClearService>.internal(
      clipboardAutoClearService,
      name: r'clipboardAutoClearServiceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$clipboardAutoClearServiceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ClipboardAutoClearServiceRef = ProviderRef<ClipboardAutoClearService>;
String _$settingsNotifierHash() => r'd1923bb4845d583c300b01e47578b8c87b9aa786';

/// See also [SettingsNotifier].
@ProviderFor(SettingsNotifier)
final settingsNotifierProvider =
    AutoDisposeAsyncNotifierProvider<
      SettingsNotifier,
      AppSettingsModel
    >.internal(
      SettingsNotifier.new,
      name: r'settingsNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$settingsNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$SettingsNotifier = AutoDisposeAsyncNotifier<AppSettingsModel>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
