// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_link_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns saved-pairing reconnects and their mobile terminal controllers.

@ProviderFor(DeviceLinkNotifier)
final deviceLinkProvider = DeviceLinkNotifierProvider._();

/// Owns saved-pairing reconnects and their mobile terminal controllers.
final class DeviceLinkNotifierProvider
    extends $NotifierProvider<DeviceLinkNotifier, void> {
  /// Owns saved-pairing reconnects and their mobile terminal controllers.
  DeviceLinkNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceLinkProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceLinkNotifierHash();

  @$internal
  @override
  DeviceLinkNotifier create() => DeviceLinkNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$deviceLinkNotifierHash() =>
    r'6b9f34e1674dccb5ef33eaf67efa22c89463e68c';

/// Owns saved-pairing reconnects and their mobile terminal controllers.

abstract class _$DeviceLinkNotifier extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
