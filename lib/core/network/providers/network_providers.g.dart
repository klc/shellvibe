// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Auto-disposing provider for [LocalPtyManager].

@ProviderFor(localPtyManager)
final localPtyManagerProvider = LocalPtyManagerProvider._();

/// Auto-disposing provider for [LocalPtyManager].

final class LocalPtyManagerProvider
    extends
        $FunctionalProvider<LocalPtyManager, LocalPtyManager, LocalPtyManager>
    with $Provider<LocalPtyManager> {
  /// Auto-disposing provider for [LocalPtyManager].
  LocalPtyManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'localPtyManagerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$localPtyManagerHash();

  @$internal
  @override
  $ProviderElement<LocalPtyManager> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LocalPtyManager create(Ref ref) {
    return localPtyManager(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LocalPtyManager value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LocalPtyManager>(value),
    );
  }
}

String _$localPtyManagerHash() => r'586576942c0a03be027627397f97981964ea0dc6';
